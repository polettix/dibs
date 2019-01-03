package Dibs::Pack::Static;
use 5.024;
use experimental qw< postderef signatures >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

extends 'Dibs::Pack';

sub BUILDARGS ($class, $args) {
   my $location = $class->_inflate_location(delete $args->{location});
   $args->{_locations} = [$location];
   return $args;
} ## end sub BUILDARGS

1;
__END__
