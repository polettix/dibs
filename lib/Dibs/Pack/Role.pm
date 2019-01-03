package Dibs::Pack::Role;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Moo::Role;
use Scalar::Util qw< blessed >;
use Dibs::Location;
no warnings qw< experimental::postderef experimental::signatures >;

requires qw< location supportable_zones >;

has id => (is => 'ro', required => 1);
has name => (is => 'ro', default => sub { $_[0]->id });
has _location => (
   coerce   => \&__inflate_location,
   init_arg => 'location',
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

sub _throw_no_good_zone ($self, @candidate_zones) {
   my $name = $self->name;
   ouch 400, "$name: cannot materialize in zone $candidate_zones[0]"
     if @candidate_zones == 1;
   my $list = join ', ', @candidate_zones;
   ouch 400, "$name: cannot materialize in any zone of ($list)";
} ## end sub _throw_no_good_zone

1;
