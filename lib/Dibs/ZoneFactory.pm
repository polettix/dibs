package Dibs::ZoneFactory;
use 5.024;
use Dibs::Zone;
use Scalar::Util 'blessed';
use Ouch qw< :trytiny_var >;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _map => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %specs_for = (@args && ref($args[0])) ? $args[0]->%* : @args;
   my %map = map {
      $_ => Dibs::Zone->new(
         name           => $_,
         container_base => $specs_for{$_}{container_base},
         host_base      => $specs_for{$_}{host_base}
        )
   } keys %specs_for;
   return {_map => \%map};
} ## end sub BUILDARGS

sub zone_for ($self, $zone) {
   return $zone if blessed($zone) && $zone->isa('Dibs::Zone');
   my $map = $self->_map;
   return $map->{$zone} if exists $map->{$zone};
   ouch 400, "no zone '$zone' available (typo?)";
}

1;
