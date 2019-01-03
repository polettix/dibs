package Dibs::Action::Factory;
use 5.024;
use Dibs::Action::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Factory';

has dibspacks_factory => (is => 'ro', required => 1);

sub instance ($self, $x, %opts) {
   my $dibspacks_factory = $self->dibspacks_factory;
   my $spec = $self->inflate($x, %opts);
   return Dibs::Action::Instance->new(
      $spec->%*,
      dibspack => $dibspacks_factory->item($spec->{dibspack}, %opts),
      zone_factory => $dibspacks_factory->zone_factory,
   );
}

sub parse ($self, $x) { return $x } # FIXME

1;
