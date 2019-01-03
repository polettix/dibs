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
            env => [{THIS => 'this'}],
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
isa_ok $dibs, 'Dibs';

my $exp_hash = {
  'step' => 'baz',
  'from' => 'foo:previous',
  'actions' => [ 'this', 'that' ],
  'env' => [ { 'THIS' => 'that' } ],
  'commit' => { 'keep' => 0 },
};
my $got_hash = $dibs->step_config_for('baz');
is_deeply $got_hash, $exp_hash, 'extends worked'
   or diag Dumper($got_hash);

done_testing();
