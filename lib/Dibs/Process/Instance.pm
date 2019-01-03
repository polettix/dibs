package Dibs::Process::Instance;
use 5.024;
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< refaddr >;
use Try::Catch;
use Dibs::Inflater 'flatten_array';
use Dibs::Docker qw< docker_commit docker_rm docker_rmi >;
use Dibs::Output;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::EnvCarrier';
with 'Dibs::Role::Identifier';

has actions_factory => (is => 'ro', required => 1);
has dibspacks_factory => (
   is => 'ro',
   lazy => 1,
   default => sub ($self) { $self->actions_factory->dibspacks_factory },
)

has actions => (is => 'ro', default => sub { return [] });
has commit  => (is => 'ro', default => undef);
has from    => (is => 'ro', required => 1);

sub run ($self, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   ARROW_OUTPUT('=', 'process ' . $self->name);

   my $image = ...;
   my $cid;
   try {
      my ($ecode, $out);
      my $actions_factory = $self->actions_factory;
      my $changes = ...;
      for my $spec (flatten_array($self->actions)) {
         my $action = $actions_factory->item($spec);
         ($ecode, $cid, $out) = $action->run(%args, process => $self);
         ouch 500, "action failed (exit code $ecode)" if $ecode;
         docker_commit($cid, $image, $changes);
         (my $__cid, $cid) = ($cid, undef);
         docker_rm($__cid);
      }
   }
   catch {
      docker_rm($cid) if defined $cid;
      docker_rmi($image);
      die $_; # rethrow
   };

   return;
}

1;
