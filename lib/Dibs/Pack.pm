package Dibs::Pack;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use Module::Runtime qw< use_module >;
use Moo;
use List::Util qw< first >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< :constants >;

has _locations => (is => 'ro', default  => []);
has name       => (is => 'ro', required => 1);

sub create ($package, $spec, $zone_factory) {

}

# interface, these MUST be overridden
sub first_material_location ($self, @candidate_zones) {
   ouch 500, $self->name . ': unimplemented';
}

sub first_supportable_zone ($self, @candidate_zones) {
   ouch 500, $self->name . ': unimplemented';
}

# protected methods, useful in derived classes
sub _first_location_in ($self, @candidate_zones) {
   my @ls = $self->_locations->@* or return undef;
   return $ls[0] unless @candidate_zones;
   my %is_candidate = map { $_ => 1 } @candidate_zones;
   return first { $is_candidate{$_->zone} } @ls;
} ## end sub location

sub _inflate_location ($self_or_package, $spec) {
   return $spec if blessed($spec) && $spec->isa('Dibs::Location');
   return Dibs::Location->new($spec) if ref($spec) eq 'HASH';
   ouch 400, q{invalid location for pack '} . $self->name . q{'};
}

1;
__END__


interface


How to use:

   my $instance = $pkg->create($spec, $zf);
   ...
   my $zone = $self->first_supportable_zone(@candidates) # also empty
      ouch 400, 'no zone found';
   my $location = $self->first_material_location($zone);

   # or rely on exceptions
   my $location = $self->first_material_location(@candidate_zones);

   # list already supported zones
   my @zones = $instance->zones(@useful_zones);

   # list all possible supported zones in provided list, falls back to
   # zones if list is empty
   my @zones = $instance->potential_zones(@useful_zone);




   my $instance = $pkg->create($specification, $zone_factory);
   ...
   my ($zone) = $instance->zones(@useful_zones)
      || $instance->add_zone($useful_zone[0]);
   my $location = $instance->materialize($zone);

   # - OR -
   my ($zone) = $instance->zones;


__END__
use Dibs::Config qw< :constants :functions >;

has container_path => (coerce => \&_path, is => 'ro', required => 1);
has host_path      => (coerce => \&_path, is => 'ro', required => 1);
has id             => (is => 'lazy');
has name           => (is => 'ro', required => 1);
has path           => (is => 'ro', default => sub { return undef } );

sub _build_id ($self) {
   our $__id //= 0;
   return ++$__id;
}

sub _path ($p) { defined($p) ? Path::Tiny::path($p) : undef }

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub create ($pkg, $sp, $dibs) {
   my ($raw, %args) = ref($sp) eq 'HASH' ? (undef, $sp->%*) : $sp->@*;
   $pkg->expand_dwim(\%args) unless defined $raw;
   my $type = delete $args{type};
   my $class = delete($args{class}) // $pkg->class_for($type);
   return $class->new($raw // \%args, $dibs);
}

sub expand_dwim ($pkg, $args) {
   if (exists($args->{run}) && !exists($args->{type})) {
      $args->{type}    = IMMEDIATE,
      $args->{program} = delete $args->{run};
   }
   return $args;
}

sub resolve_paths ($self, $path = \undef) {
   $path = $self->path if ref($path) eq 'SCALAR' && !defined($$path);
   return map {
      my $p = $self->$_;
      $p = $p->child($path) if defined($p) && defined($path);
      ($_ => $p);
   } qw< container_path host_path >;
}

sub type ($self) { return lc((ref($self) || $self) =~ s{.*::}{}mxsr) }

1;
__END__
