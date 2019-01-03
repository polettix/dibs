use strict;
use Test::More;
use Path::Tiny qw< path cwd >;
use Dibs;
use Dibs::Config ':all';
use experimental qw< postderef signatures >;
use lib path(__FILE__)->parent->stringify;
use DibsTest;
no warnings qw< experimental::postderef experimental::signatures >;

my $work_dir = path(__FILE__ . '.d')->absolute;
clean_environment();
my $config = get_config_cmdenv([ -C => $work_dir, qw< foo bar > ]);
is cwd->stringify, $work_dir->stringify, 'changed directory';
is_deeply $config->{do}, [qw< foo bar >], 'config positionals';

$config = add_config_file($config, $work_dir->child('dibs.yml'));
use Data::Dumper;
diag Dumper $config;

my $dibs = Dibs->new($config);
isa_ok $dibs, 'Dibs';
is $dibs->name, $config->{name}, 'name';
is $dibs->project_dir, $work_dir->child('dibs'), 'project_dir';
can_ok $dibs, qw< action_factory pack_factory zone_factory sketch >;

my $sketch = $dibs->sketch($config->{do});
isa_ok $sketch, 'Dibs::Action::Sketch';
can_ok $sketch, qw< draw execute >;

my $actions = $sketch->actions;
is scalar(@$actions), 2, 'right number of actions in sketch';
isa_ok $_, 'Dibs::Action' for @$actions;
can_ok $actions->[0], qw< execute output output_marked >;



done_testing();
__END__
