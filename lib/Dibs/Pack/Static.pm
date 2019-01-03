package Dibs::Pack::Static;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Pack';

# for static stuff, there's nothing to materialize really because we expect
# it to be there already. Otherwise, complain loudly.
sub location ($self, @candidate_zones) {
   return $self->_location if $self->supportable_zones(@candidate_zones);
   $self->_throw_no_good_zone(@candidate_zones);
} ## end sub location

# only support what's already in place
sub supportable_zones ($self, @candidate_zones) {
   my $location = $self->_location;
   return $location->zone unless @candidate_zones;

   my $zone = $location->zone;
   return grep { $zone->equals($_) } @candidate_zones;
}

1;
__END__
