package Dibs::Sketch::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Sketch::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has stroke_factory   => (is => 'ro', required => 1);
has dibspack_factory => (
   is => 'ro',
   lazy => 1,
   default => sub ($self) { $self->stroke_factory->dibspack_factory },
);

with 'Dibs::Role::Factory';

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);
   return Dibs::Sketch::Instance->new(
      $spec->%*,
      stroke_factory   => $self->stroke_factory,
      dibspack_factory => $self->dibspack_factory,
   );
}

sub parse ($self, $x) {
   ouch 400, "cannot parse process '$x'";
}

1;
