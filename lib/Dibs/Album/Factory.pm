package Dibs::Album::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Album::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has sketch_factory => (is => 'ro', required => 1);
has dibspack_factory => (
   is      => 'ro',
   lazy    => 1,
   default => sub ($self) { $self->stroke_factory->dibspack_factory },
);

with 'Dibs::Role::Factory';

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);
   state $id = 0;
   return Dibs::Album::Instance->new(
      id               => $id++,
      $spec->%*,
      album_factory    => $self,
      sketch_factory   => $self->sketch_factory,
      dibspack_factory => $self->dibspack_factory,
   );
} ## end sub instance

around parse => sub ($orig, $self, $x) {
   return {sections => $x} if ref($x) eq 'ARRAY';
   return $self->$orig($x);
};

sub parsex ($self, $x) {
   my $ref = ref $x;
   return $x if $ref eq 'HASH';
   return {sections => $x} if $ref eq 'ARRAY';
   ouch 400, "cannot parse album '$x'";
}

1;
