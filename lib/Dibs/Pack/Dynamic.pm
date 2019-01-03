package Dibs::Pack::Dynamic;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Pack';

has cloner    => (is => 'ro', default  => undef);
has fetcher   => (is => 'ro', required => 1);
has materials => (is => 'ro', default  => sub { {} }, init_arg => undef);

sub location ($self, @candidate_zones) {
   my $base_location = $self->_location;
   @candidate_zones = $base_location->zone unless @candidate_zones;

   # look in cache first
   my $avail = $self->materials;
   for my $candidate (@candidate_zones) {
      return $avail->{$candidate->id} if exists $avail->{$candidate->id};
   }

   # we have to either fetch or to clone something
   my ($fetcher, $cloner) = ($self->fetcher, $self->cloner);
   for my $candidate (@candidate_zones) {
      next unless $candidate->host_base;    # can only work from host side
      my $location = $base_location->clone_in($candidate);
      if (scalar(keys $avail->%*) && $cloner) {  # already fetched, "clone"
         ref($cloner) eq 'CODE'
           ? $cloner->($location, $avail)
           : $cloner->clone_in($location, $avail);
      }
      else {    # first time or no cloner available, fetch again
         ref($fetcher) eq 'CODE'
           ? $fetcher->($location)
           : $fetcher->materialize_in($location);
      }
      return($avail->{$candidate->id} = $location);
   } ## end for my $candidate (@candidate_zones)

   # no luck if we arrived here, throw a meaningful exception
   $self->_throw_no_good_zone(@candidate_zones);
} ## end sub location

# whatever is visible within the host is fine
sub supportable_zones ($self, @candidate_zones) {
   return grep { defined($_->host_base) } @candidate_zones;
}

1;
__END__
