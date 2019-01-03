use strict;
use Test::More;
use Data::Dumper;
use Dibs;

my $dibs = Dibs->new(
   config => {
      steps => {
         foo => {
            step => 'foo',
            from => 'foo:previous',
         },
         bar => {
            step => 'bar',
            from => 'bar:previous',
            actions => [qw< this that >],
         },
         baz => {
            step => 'baz',
            extends => [qw< foo bar >],
            env => [{THIS => 'that'}],
         },
      },
   },
);
my $hash = $dibs->step_config_for('baz');
is_deeply $hash, {}, 'extends worked'
   or diag Dumper($hash);
isa_ok $dibs, 'Dibs';

done_testing();

__END__
use Path::Tiny qw< path cwd >;
use Dibs;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

my $work_dir = path(__FILE__ . '.d')->absolute;
clean_environment();
my $dibs = Dibs->create_from_cmdline(
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

my $prj_dir = $work_dir->child('dibs');
is $dibs->project_dir, $prj_dir, 'project_dir';

is $dibs->project_dir($_), $prj_dir->child($_), "dir $_ in project"
   for qw< cache dibspacks empty env src >;

is $dibs->resolve_container_path($_), "/tmp/$_", "dir $_ in container"
   for qw< cache dibspacks env src >;

ok   $dibs->config('development'), 'development set';
ok ! $dibs->config('alien'), 'alien not set';
ok ! $dibs->config('local'), 'local not set';

is $dibs->config('origin'), $work_dir, 'origin set for development';

my @actions = $dibs->actions_for('foo');
is scalar(@actions), 1, 'one dibspack defined for foo';
isa_ok $actions[0], $_ for qw< Dibs::Action >;

ok length($actions[0]->name), 'dibspack has a name';

$work_dir->child('dibs')->remove_tree({safe => 0});
done_testing();

sub clean_environment { delete @ENV{(grep {/^DIBS_/} keys %ENV)} }
