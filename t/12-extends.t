use strict;
use Test::More;
use Data::Dumper;
use Dibs;

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
   pack => { run => 'foo' },
   args => [1..3],
   env => [{THIS => 'that'}],
};
my $got_hash = $dibs->action_factory->inflate($config->{actions}{baz});
is_deeply $got_hash, $exp_hash, 'extends worked'
   or diag Dumper $got_hash;

is_deeply $config->{actions}{baz}, $exp_hash, 'extension in cached conf',
   or diag Dumper $config;

my $stroke = $dibs->instance('baz');
isa_ok $stroke, 'Dibs::Action::Stroke';

done_testing();
