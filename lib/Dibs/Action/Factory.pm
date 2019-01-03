package Dibs::Action::Factory;
use 5.024;
use Dibs::Action::Instance;
use Ouch ':trytiny_var';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has dibspacks_factory => (is => 'ro', required => 1);

with 'Dibs::Role::Factory';

sub instance ($self, $x, %args) {
   my $dibspacks_factory = $self->dibspacks_factory;
   my $spec = $self->inflate($x, %args);
   return Dibs::Action::Instance->new(
      $spec->%*,
      dibspack => $dibspacks_factory->item($spec->{dibspack}, %args),
      zone_factory => $dibspacks_factory->zone_factory,
   );
}

sub parse ($self, $x) {
   ouch 400, "cannot parse action '$x'";
}

1;
