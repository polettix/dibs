package Dibs::Role::Pack;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Moo::Role;
use Scalar::Util qw< blessed >;
use Dibs::Location;
no warnings qw< experimental::postderef experimental::signatures >;

has id => (is => 'ro', required => 1);
has name => (is => 'ro', default => sub { $_[0]->id });
has location => (
   coerce   => \&__inflate_location,
   is       => 'ro',
   isa      => \&__assert_location,
   required => 1,
);

sub __assert_location ($location) {
   return if blessed($location) && $location->isa('Dibs::Location');
   ouch 400, "$location is not a Dibs::Location";
}

sub __inflate_location ($spec) {
   return $spec if blessed($spec) && $spec->isa('Dibs::Location');
   return Dibs::Location->new($spec) if ref($spec) eq 'HASH';
   ouch 400, "invalid location '$spec' for dibspack";
}

sub container_path ($s, $p) { $s->location->container_path($p) }
sub host_path      ($s, $p) { $s->location->host_path($p) }

1;
