use strict;
use 5.024;
use Ouch qw< :trytiny_var >;
use Test::More;
use Test::Exception;

use Path::Tiny qw< path cwd >;
use lib path(__FILE__)->parent->stringify;
use DibsTest;

plan skip_all => "bot docker and git MUST be available for this test"
  unless has_docker() && has_git();

use Dibs;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use Data::Dumper;

clean_environment();

my $work_dir = path(__FILE__ . '.d')->absolute;
my $guard = directory_guard($work_dir);
init_git($work_dir);

diag 'this may take a little while';

my $dibs = Dibs->create_from_cmdline(
   -C => $work_dir,
   qw< foo bar >
);
isa_ok $dibs, 'Dibs';

my ($err, $out);
lives_ok {
   local *STDERR;
   open STDERR, '>', \$err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   $dibs->run;
} 'call to dibs->run survives'
   or diag bleep();

#diag Dumper \@collected;
is $out, undef, 'output of the whole thing';

for my $sentence (
      'Hello, world! This is foo',
      'Hello, world! This is bar [one] [two (2)]',
) {
   like $err, qr{\Q$sentence\E}, "sentence: $sentence";
}

done_testing();
