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

use constant INSIDE  => 'inside';
use constant GIT     => 'git';
use constant PROJECT => 'project';
use constant SRC     => 'src';

has specification  => (is => 'ro', required => 1);
has host_path      => (is => 'ro', required => 1);
has container_path => (is => 'ro', required => 1);
has type           => (is => 'ro', required => 1);

sub __split_first_directory ($path) {
   my $root = Path::Tiny->rootdir;
   my $abs = $path->absolute($root);
   $abs = $abs->parent while ! $abs->parent->is_rootdir;
   my $first = $abs->relative($root)->stringify;
   return ($first, $path->relative($first));
}

sub create ($package, $config, $specification) {
   return $package->_create_git($config, $specification)
      if $specification =~ m{\A (?: http s? | git | ssh ) :// }imxs;
   
   my $path = path($specification);
   return $package->_create_inside($config, $specification) if $path->is_absolute;

   my ($first, $subpath) = __split_first_directory($path);
   return $package->_create_project($config, $specification, $subpath)
      if $first eq PROJECT;
   return $package->_create_src($config, $specification, $subpath)
      if $first eq SRC;

   ouch 400, "unsupported dibspack $specification";
}

sub __resolve_paths ($config, $path, $bh, $bc) {
   $log->debug("__resolve_paths(@_)");
   my $hp = path($config->{project_dir})->child($config->{$bh}, $path);
   my $cp = path($config->{$bc}, $path);
   return (
      host_path => $hp->stringify,
      container_path => $cp->stringify,
   );
}

sub _create_project ($package, $config, $spec, $subpath) {
   return $package->new(
      type => PROJECT,
      specification => $spec,
      __resolve_paths($config, $subpath, 
         qw< project_dibspacks_dir container_dibspacks_dir >),
   );
}

sub _create_src ($package, $config, $spec, $subpath) {
   return $package->new(
      type => SRC,
      specification => $spec,
      __resolve_paths($config, $subpath, 
         qw< project_src_dir container_src_dir >),
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
      __resolve_paths($config, path(GIT, $name)->stringify,
         qw< project_dibspacks_dir container_dibspacks_dir >),
   );
}

sub fetch ($self) {
   return unless $self->type eq GIT;
   require Dibs::Git;
   Dibs::Git::fetch($self->specification, $self->host_path);
}

1;
__END__
