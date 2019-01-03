package Dibs::Pack::Static;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

extends 'Dibs::Pack';

# for static stuff, we actually support providing one single location
sub BUILDARGS ($class, $args) {
   my $location = $class->_inflate_location(delete $args->{location});
   $args->{_locations} = [$location];
   return $args;
}

# for static stuff, there's nothing to materialize really because we expect
# it to be there already. Otherwise, complain loudly.
sub first_material_location ($self, @candidate_zones) {
   if (my $l = $self->location(@candidate_zones)) { return $l }
   my $name = $self->name;
   ouch 500, "$name: bug, no zone seems supported" unless @candidate_zones;
   ouch 400, "$name: cannot materialize in zone $candidate_zones[0]"
     if @candidate_zones == 1;
   my $list = join ', ', @candidate_zones;
   ouch 400, "$name: cannot materialize in any zone of ($list)";
} ## end sub first_material_location

# only support what's already in place
sub first_supportable_zone ($self, @candidate_zones) {
   my $l = $self->_first_location_in(@candidate_zones) or return undef;
   return $l->zone;
}

1;
__END__
