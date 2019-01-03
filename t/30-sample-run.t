use strict;
use 5.024;
use Ouch qw< :trytiny_var >;
use Test::More;

use Path::Tiny qw< path cwd >;
use lib path(__FILE__)->parent->stringify;
use DibsTest;

plan skip_all => "both docker and git MUST be available for this test"
  unless has_docker() && has_git();

diag 'takes a bit...';

use Dibs::App ();
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use Data::Dumper;

clean_environment();

my $work_dir = path(__FILE__ . '.d')->absolute;
my $guard = directory_guard($work_dir);
init_git($work_dir);

my ($retval, $err, $out);
{
   local *STDERR;
   open STDERR, '>', \$err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   $retval = Dibs::App::main(-C => $work_dir, qw< foo bar >);
}
is $retval, 0, 'main() outcome';

is $out, undef, 'output of the whole thing';
#diag Dumper $err;

for my $sentence (
      'Hello, world! In foo, FOO starts as <>',
      'Hello, world! This is foo and FOO is <bar>',
      'FOO<bar> BAR<baaaz>',
      'Hello, world! This is bar [one] [two (2)]',
      '-----> stroke bar! bar! bar!',
      '-----> stroke foo! Foo! FOO!',
) {
   like $err, qr{\Q$sentence\E}, "sentence: $sentence";
}

done_testing();
