use strict;
use 5.024;
use Test::More;
use Test::Exception;
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
use Dibs::Config ':all';
use Dibs::App ();
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use Data::Dumper;

clean_environment();

my $work_dir = path(__FILE__ . '.d')->absolute;
my $guard = directory_guard($work_dir);

my $config = get_config_cmdenv([ -C => $work_dir, qw< -D foo bar > ]);
$config = add_config_file($config, $work_dir->child('dibs.yml'));
$config->{run_variables}{DIBS_ID} = 'testing';

my ($err, $out);
lives_ok {
   local *STDERR;
   open STDERR, '>', \$err;
   local *STDOUT;
   open STDOUT, '>', \$out;
   Dibs::App::draw($config);
} 'Dibs::App::draw lives';

#diag Dumper \@collected;
check_collected_actions(@collected);
is $out, "foo:latest\n", 'output of the whole thing';

done_testing();

sub check_collected_actions (@got) {
   subtest 'collected actions' => sub {
      my @expected = (
         [qw< docker tag alpine:latest dibstest:testing >],
         [qw< docker run --cidfile >],
         [qw< docker commit -c >],
         [qw< docker rm >],
         [qw< docker tag dibstest:testing foo:latest >],
         [qw< docker tag alpine:latest >],
         [qw< docker run --cidfile >],
         [qw< docker commit -c >],
         [qw< docker rm  >],
         [qw< docker rmi dibstest:testing >],
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
