package Dibs::ZoneFactory;
use 5.024;
use Dibs::Zone;
use Scalar::Util 'blessed';
use Ouch qw< :trytiny_var >;
use Path::Tiny 'path';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _map => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %specs = (@args && ref($args[0])) ? $args[0]->%* : @args;
   my $zone_specs_for = $specs{zone_specs_for};
   my $project_dir =
     defined($specs{project_dir}) ? path($specs{project_dir}) : undef;
   my %map = map {
      my $spec = $zone_specs_for->{$_};
      my $zone;
      if (blessed($spec) && $spec->isa('Dibs::Zone')) {
         $zone = $spec;
      }
      else {
         my $host_base = $spec->{host_base};
         if (defined $host_base) {
            $host_base = path($host_base);
            $host_base = $project_dir->child($host_base)
               if defined($project_dir) && $host_base->is_relative;
         }
         $zone = Dibs::Zone->new(
            name           => $_,
            container_base => $spec->{container_base},
            host_base      => $host_base,
         );
      }
      $_ => $zone;
   } keys $zone_specs_for->%*;
   return {_map => \%map};
} ## end sub BUILDARGS

sub zone_for ($self, $zone) {
   return $zone if blessed($zone) && $zone->isa('Dibs::Zone');
   my $map = $self->_map;
   return $map->{$zone} if exists $map->{$zone};
   ouch 400, "no zone '$zone' available (typo?)";
} ## end sub zone_for

1;
