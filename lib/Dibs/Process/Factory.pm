package Dibs::Process::Factory;
use 5.024;
use Ouch qw< :trytiny_var >;
use Dibs::Process::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Factory';

has actions_factory   => (is => 'ro', required => 1);
has dibspacks_factory => (
   is => 'ro',
   lazy => 1,
   default => sub ($self) { $self->actions_factory->dibspacks_factory },
);

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);
   return Dibs::Process::Instance->new(
      $spec->%*,
      actions_factory   => $self->actions_factory,
      dibspacks_factory => $self->dibspacks_factory,
   );
}

sub parse ($self, $x) { return $x } # FIXME

1;
