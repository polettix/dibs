package Dibs::Action::Factory;
use 5.024;
use Dibs::Action::Instance;
use Ouch ':trytiny_var';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has dibspack_factory => (is => 'ro', required => 1);

with 'Dibs::Role::Factory';

sub instance ($self, $x, %args) {
   my $dibspack_factory = $self->dibspack_factory;
   my $spec = $self->inflate($x, %args);
   return Dibs::Action::Instance->new(
      $spec->%*,
      dibspack => $dibspack_factory->item($spec->{dibspack}, %args),
      zone_factory => $dibspack_factory->zone_factory,
   );
}

sub parse ($self, $x) {
   ouch 400, "cannot parse action '$x'";
}

1;
