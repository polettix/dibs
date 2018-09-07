use strict;
use 5.024;
use Test::More;
use Path::Tiny qw< path cwd >;
use Dibs::Run;

use lib path(__FILE__)->parent->stringify;
use DibsTest;

use Test2::Mock;
my ($mocker, @collected);
BEGIN {
   $mocker = Test2::Mock->new(
      class => 'Dibs::Run',
      override => [
         run_command => sub { push @collected, [@_]; return 0 },
         run_command_out => sub { push @collected, [@_]; return (0, 'yay') },
      ],
   );
}

use Dibs;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use Data::Dumper;

clean_environment();

my $work_dir = path(__FILE__ . '.d')->absolute;
my $guard = directory_guard($work_dir);
my $dibs = Dibs->create_from_cmdline(
   -C => $work_dir,
   qw< foo bar >
);
isa_ok $dibs, 'Dibs';

$dibs->ensure_host_directories;
is_deeply \@collected, [
   [
      [ 'git', 'clone', $work_dir->stringify,
         $work_dir->child(qw< dibs src >)->stringify ],
      7
   ]
], 'called right command for cloning repo';

@collected = ();

my $out;
{
   local *STDERR;
   open STDERR, '>', \my $err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   $dibs->run;
}

#diag Dumper \@collected;
check_collected_actions(@collected);
is $out, "foo: foo:latest\n", 'output of the whole thing';

done_testing();

sub check_collected_actions (@got) {
   subtest 'collected actions' => sub {
      my @expected = (
         [qw< git clone >],
         [qw< docker tag alpine:latest >],
         [qw< docker run --cidfile >],
         [qw< docker commit -c >],
         [qw< docker rm >],
         [qw< docker tag >],
         [qw< docker rmi >],
         [qw< docker tag alpine:latest >],
         [qw< docker run --cidfile >],
         [qw< docker commit -c >],
         [qw< docker rm  >],
         [qw< docker rmi >],
      );
      is scalar(@got), scalar(@expected), 'number of actions as expected';
      for my $i (0 .. $#expected) {
         my $got = $got[$i];
         my $exp = $expected[$i];
         subtest join(' ', $exp->@*, '...') => sub {
            for my $j (0 .. $#$exp) {
               is $got->[0][$j], $exp->[$j], "$exp->[$j]"
            }
         }
      }
   };
}
