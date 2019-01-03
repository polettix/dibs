use strict;
use Test::More;
use Test::Exception;
use Path::Tiny qw< path cwd >;
use Dibs::Config ':all';
use Dibs;
use Dibs::App ();
use experimental qw< postderef signatures >;
use lib path(__FILE__)->parent->stringify;
use DibsTest;
no warnings qw< experimental::postderef experimental::signatures >;

plan skip_all => "docker MUST be available for this test"
  unless has_docker();

diag 'takes a bit...';

my $work_dir = path(__FILE__ . '.d')->absolute;
clean_environment();
my $guard = directory_guard($work_dir);
$work_dir->child('cache')->remove_tree({safe => 0});

my $config = get_config_cmdenv([ '-A', -C => $work_dir, qw< foo bar > ]);
is cwd->stringify, $work_dir->stringify, 'changed directory';
is_deeply $config->{do}, [qw< foo bar >], 'config positionals';

$config = add_config_file($config, $work_dir->child('dibs.yml'));

my $dibs = Dibs->new($config);
isa_ok $dibs, 'Dibs';
is $dibs->name, $config->{name}, 'name';
is $dibs->project_dir, $work_dir, 'project_dir';
can_ok $dibs, qw< action_factory pack_factory zone_factory sketch >;

my $sketch = $dibs->sketch($config->{do});
isa_ok $sketch, 'Dibs::Action::Sketch';
can_ok $sketch, qw< draw execute >;

my $actions = $sketch->actions;
is scalar(@$actions), 2, 'right number of actions in sketch';
isa_ok $_, 'Dibs::Action' for @$actions;
can_ok $actions->[0], qw< execute output output_marked >;

$config->{run_variables} = {
   DIBS_ID => 'testing',
};

my $out;
lives_ok { $out = Dibs::App::draw($config) } 'call to Dibs::App::draw';

is_deeply $out->{out}, [
  [
    'sketch',
    [
      [ 'prepare', undef ],
      [ 'stroke', "Hello, world! This is foo (one two (2))\n" ]
    ]
  ],
  [
    'sketch',
    [
      [ 'prepare', undef ],
      [ 'stroke', "Hello, world! This is bar (one two (2))\n" ]
    ]
  ]
], 'output from call to draw';

ok $work_dir->child('cache')->exists, 'cache dir created';

done_testing();
__END__
