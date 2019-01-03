use strict;
use 5.024;
use Ouch qw< :trytiny_var >;
use Test::More;

use Path::Tiny qw< path cwd >;
use lib path(__FILE__)->parent->stringify;
use DibsTest;

plan skip_all => "bot docker and git MUST be available for this test"
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
$work_dir->child('show-stopper')->spew_raw('Howdy!');

my ($retval, $err, $out);
{
   local *STDERR;
   open STDERR, '>', \$err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   $retval = Dibs::App::main(-C => $work_dir, qw< foo bar >);
}
isnt $retval, 0, 'main failed with dirty state';
like $err, qr{dirty state not allowed}, 'dirty state complains by default';

{
   local *STDERR;
   open STDERR, '>', \$err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   $retval = Dibs::App::main(-C => $work_dir, qw< --dirty foo bar >);
}
is $retval, 0, 'main succeeded with dirty state and authorization';

#diag Dumper \@collected;
is $out, undef, 'output of the whole thing';

for my $sentence (
      'Hello, world! This is foo',
      'Hello, world! This is bar [one] [two (2)]',
) {
   like $err, qr{\Q$sentence\E}, "sentence: $sentence";
}

done_testing();
