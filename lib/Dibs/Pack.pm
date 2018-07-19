package Dibs::Pack;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny qw< path >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< DIBSPACKS GIT INSIDE PROJECT SRC >;

has specification  => (is => 'ro', required => 1);
has host_path      => (is => 'ro', required => 1);
has container_path => (is => 'ro', required => 1);
has type           => (is => 'ro', required => 1);

sub create ($package, $config, $specification) {
   return $package->_create_git($config, $specification)
      if $specification =~ m{\A (?: http s? | git | ssh ) :// }imxs;

   if (my ($type, $subpath) = split m{:}mxs, $specification, 2) {
      return $package->_create_project($config, $specification, $subpath)
         if $type eq PROJECT;
      return $package->_create_src($config, $specification, $subpath)
         if $type eq SRC;
   }

   return $package->_create_inside($config, $specification)
      if path($specification)->is_absolute;

   ouch 400, "unsupported dibspack $specification";
}

sub __resolve_paths ($config, $path, $zone_name) {
   $log->debug("__resolve_paths(@_)");
   my $pd = path($config->{project_dir})->absolute;
   my $hp = $pd->child($config->{project_dirs}{$zone_name}, $path);
   my $cp = path($config->{container_dirs}{$zone_name}, $path);
   return (
      host_path      => $hp->stringify,
      container_path => $cp->stringify,
   );
}

sub _create_project ($package, $config, $spec, $subpath) {
   return $package->new(
      type => PROJECT,
      specification => $spec,
      __resolve_paths($config, $subpath, DIBSPACKS),
   );
}

sub _create_src ($package, $config, $spec, $subpath) {
   return $package->new(
      type => SRC,
      specification => $spec,
      __resolve_paths($config, $subpath, SRC),
   );
}

sub _create_inside ($package, $config, $specification) {
   return $package->new(
      type => INSIDE,
      specification  => $specification,
      host_path => undef,
      container_path => $specification,
   );
}

sub _create_git ($package, $config, $uri) {
   require Digest::MD5;
   my $name = Digest::MD5::md5_hex($uri);
   my ($pd, $pdd) = $config->@{qw< project_dir project_dibspacks_dir >};
   my $host_path = path($pd)->child($pdd, GIT, $name);
   return $package->new(
      type => GIT,
      specification => $uri,
      __resolve_paths($config, path(GIT, $name)->stringify, DIBSPACKS),
   );
}

sub fetch ($self) {
   return unless $self->type eq GIT;
   require Dibs::Git;
   Dibs::Git::fetch($self->specification, $self->host_path);
}

1;
__END__
