use strict;
use Test::More;
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
is_deeply [$dibs->steps], [qw< foo bar >], 'steps are OK';
is_deeply [sort {$a cmp $b} keys $dibs->dconfig->%*], [qw< bar foo >],
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

my @dibspacks = $dibs->dibspacks_for('foo');
is scalar(@dibspacks), 1, 'one dibspack defined for foo';
isa_ok $dibspacks[0], $_ for qw< Dibs::Pack Dibs::Pack::Immediate >;
like $dibspacks[0]->program, qr{\A\#!/bin/sh\s}mxs,
   'program probably as expected';

ok length($dibspacks[0]->name), 'dibspack has a name';

done_testing();

sub clean_environment { delete @ENV{(grep {/^DIBS_/} keys %ENV)} }
