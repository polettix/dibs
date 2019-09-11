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

   # base project directory paths for container and host respectively.
   # Each might be undefined, although it's higly unlikely for
   # project_dir and also for host_project_dir if running dibs
   # properly from a container itself.
   my $project_dir = __path_or_undef($specs{project_dir});
   my $host_project_dir = __path_or_undef($specs{host_project_dir});

   my $zone_specs_for = $specs{zone_specs_for};
   my %map = map {
      my $spec = $zone_specs_for->{$_};
      my $zone;
      if (blessed($spec) && $spec->isa('Dibs::Zone')) {
         $zone = $spec;
      }
      else {
         my $host_base = $spec->{host_base};
         my $realhost_base = undef;
         if (defined $host_base) {
            $host_base = path($host_base);
            $host_base = $project_dir->child($host_base)
               if $project_dir && $host_base->is_relative;
            $host_base = $host_base->absolute if $host_base->is_relative;

            $realhost_base = $host_project_dir->child(
               $host_base->relative($project_dir))->absolute
               if $host_project_dir && $project_dir
                  && $project_dir->subsumes($host_base);
            $realhost_base //= $host_base;
         }
         $zone = Dibs::Zone->new(
            $spec->%*,
            host_base => $host_base,
            realhost_base => $realhost_base,
            name      => $_,
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

sub default ($class, $project_dir = undef, $host_project_dir = undef) {
   require Dibs::Config;
   $project_dir //= cwd->absolute;
   my $defaults = Dibs::Config::DEFAULTS();
   return Dibs::Zone::Factory->new(
      project_dir => $project_dir,
      host_project_dir => $host_project_dir,
      zone_specs_for => $defaults->{zone_specs_for},
      zone_names_for => $defaults->{zone_names_for},
   );
}

sub __path_or_undef ($x) { return defined $x ? path($x) : undef }

1;
