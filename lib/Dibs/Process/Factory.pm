package Dibs::Process::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Process::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has action_factory   => (is => 'ro', required => 1);
has dibspack_factory => (
   is => 'ro',
   lazy => 1,
   default => sub ($self) { $self->action_factory->dibspack_factory },
);

with 'Dibs::Role::Factory';

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);
   return Dibs::Process::Instance->new(
      $spec->%*,
      action_factory   => $self->action_factory,
      dibspack_factory => $self->dibspack_factory,
   );
}

sub parse ($self, $x) {
   ouch 400, "cannot parse process '$x'";
}

1;
