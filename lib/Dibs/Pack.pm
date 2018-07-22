package Dibs::Pack;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny qw< path >;
use List::Util qw< any >;
use Try::Catch;
use Module::Runtime qw< use_module >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';

has name           => (is => 'ro', required => 1);
has host_path      => (is => 'ro', required => 1);
has container_path => (is => 'ro', required => 1);

sub _build_name ($self) { return $self->origin }

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub create ($pkg, $config, $spec) {
   if (my $sref = ref $spec ) {
      ouch 400, "invalid reference of type '$sref' for dibspack"
         unless $sref eq 'HASH';
      my %spec = $spec->%*;
      return $pkg->class_for(delete $spec{type})->new($config, %spec);
   }

   # optimize for git
   return $pkg->class_for('git')->parse_new($config, $spec, $spec)
      if $spec =~ m{\A (?: http s? | git | ssh ) :// }imxs;

   # otherwise the type must be encoded in the spec
   my ($type, $data) = split m{:}mxs, $spec, 2;
   return $pkg->class_for($type)->parse_new($config, $data, $spec);
}

sub resolve_host_path ($class, $config, $zone, $path) {
   my $pd = path($config->{project_dir})->absolute;
   $log->debug("project dir $pd");
   my $zd = $config->{project_dirs}{$zone};
   $log->debug("zone <$zd> path<$path>");
   return $pd->child($zd, $path)->stringify;
}

sub resolve_container_path ($class, $config, $zone, $path) {
   return path($config->{container_dirs}{$zone}, $path)->stringify;
}

sub _create_inside ($package, $config, $specification) {
   return $package->new(
      type => INSIDE,
      specification  => $specification,
      host_path => undef,
      container_path => $specification,
   );
}

sub fetch { return }

sub has_program ($self, $program) {
   return (!defined($self->host_path))
       || -x path($self->host_path, $program)->stringify;
}

1;
__END__
