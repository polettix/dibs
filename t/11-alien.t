use strict;
use Test::More;
use Path::Tiny qw< path cwd >;
use Dibs;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

my $work_dir = path(__FILE__ . '.d')->absolute;
clean_environment();
my $dibs = Dibs->create_from_cmdline(
   '--alien',
   -C => $work_dir,
   qw< foo bar >
);

isa_ok $dibs, 'Dibs';
is cwd->stringify, $work_dir->stringify, 'changed directory';
is_deeply [$dibs->workflow], [qw< foo bar >], 'workflow is OK';
is_deeply [sort {$a cmp $b} keys $dibs->sconfig->%*], [qw< bar foo >],
   'definitions';

is $dibs->name('bar'), 'dibstest', 'name method (bar definition)';
is $dibs->name('foo'), 'foo', 'name method (foo definition)';

my $prj_dir = $work_dir;
is $dibs->project_dir, $prj_dir, 'project_dir';

is $dibs->project_dir($_), $prj_dir->child($_), "dir $_ in project"
   for qw< cache dibspacks empty env src >;

is $dibs->resolve_container_path($_), "/tmp/$_", "dir $_ in container"
   for qw< cache dibspacks env src >;

ok ! $dibs->config('development'), 'development set';
ok   $dibs->config('alien'), 'alien not set';
ok ! $dibs->config('local'), 'local not set';

ok !defined($dibs->config('origin')), 'origin unset by default in alien';

my @actions = $dibs->actions_for('foo');
is scalar(@actions), 1, 'one dibspack defined for foo';
isa_ok $actions[0], $_ for qw< Dibs::Action >;

ok length($actions[0]->name), 'dibspack has a name';

$dibs->wipe_directory('src');
ok !$work_dir->child('src')->exists,
   'src directory does not exists previously';
$dibs->ensure_host_directories;
ok $work_dir->child('src')->exists, 'src directory created';

$dibs->wipe_directory($_) for qw< cache env dibspacks src >;
done_testing();

sub clean_environment { delete @ENV{(grep {/^DIBS_/} keys %ENV)} }
