package Dibs::Zone::Factory;
use 5.024;
use Dibs::Zone;
use Scalar::Util 'blessed';
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path cwd >;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _map => (is => 'ro', required => 1);
has _zones_for => (is => 'ro', required => 1);

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

   my %zones_for;
   if (defined(my $href = $specs{zone_names_for})) {
      while (my ($key, $names) = each $href->%*) {
         $zones_for{$key} = \my @zones;
         for my $name ($names->@*) {
            ouch 400, "unknown zone $name" unless exists $map{$name};
            push @zones, $map{$name};
         }
      }
   }

   return {_map => \%map, _zones_for => \%zones_for};
} ## end sub BUILDARGS

sub zone_for ($self, $zone) {
   return $zone if blessed($zone) && $zone->isa('Dibs::Zone');
   my $map = $self->_map;
   return $map->{$zone} if exists $map->{$zone};
   ouch 400, "no zone '$zone' available (typo?)";
} ## end sub zone_for

sub item ($self, $zone) { return $self->zone_for($zone) }

sub items ($self, $filter = undef) {
   if (defined $filter) {
      my $zones_for = $self->_zones_for;
      ouch 400, "invalid filter $filter for zones filtering"
         unless exists $zones_for->{$filter};
      return $zones_for->{$filter}->@*;
   }
   else {
      return values $self->_map->%*;
   }
}

sub default ($class, $project_dir = undef) {
   require Dibs::Config;
   $project_dir //= cwd->absolute;
   my $defaults = Dibs::Config::DEFAULTS();
   return Dibs::Zone::Factory->new(
      project_dir => $project_dir,
      zone_specs_for => $defaults->{zone_specs_for},
      zone_names_for => $defaults->{zone_names_for},
   );
}

1;
