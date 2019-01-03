use strict;
use Test::More;
use Data::Dumper;
use Dibs;
#use Log::Any::Adapter qw< Stderr log_level TRACE >;

my $config = {
   project_dir => '.',
   actions => {
      foo => {
         pack => { run => 'foo' }
      },
      bar => {
         pack => { run => 'bar' },
         args => [1..3],
      },
      baz => {
         extends => [qw< foo bar >],
         env => [{THIS => 'that'}],
      },
   },
};
my $dibs = Dibs->new($config);
isa_ok $dibs, 'Dibs';

my $exp_hash = {
   args => [1..3],
   env => [{THIS => 'that'}],
   extends => [qw< foo bar >],
   pack => { run => 'foo' },
   breadcrumbs => [
      [
         {
            env => [{THIS => 'that'}],
            extends => [qw< foo bar >],
         },
         {
            env => [{THIS => 'that'}],
            extends => [qw< foo bar >],
         },
      ],
      [qw< foo foo >],
      [
         { pack => { run => 'foo' } },
         { pack => { run => 'foo' } },
      ],
   ],
};
my $got_hash = $dibs->action_factory->inflate($config->{actions}{baz});
is_deeply $got_hash, $exp_hash, 'extends worked'
   or diag Dumper $got_hash;

ok !exists($config->{actions}{baz}{args}), 'passed conf not touched';

my $got_2_hash = $dibs->action_factory->inflate('baz');
unshift @{$exp_hash->{breadcrumbs}}, [qw< baz baz >];
is_deeply $got_2_hash, $exp_hash, 'initial breadcrumb with name ';

my $stroke = $dibs->instance('baz');
isa_ok $stroke, 'Dibs::Action::Stroke';

done_testing();
