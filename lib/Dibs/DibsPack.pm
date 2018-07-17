package Dibs::DibsPack;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Moo;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path >;
no warnings qw< experimental::postderef experimental::signatures >;

use constant BIN => 'bin';
use constant PROJECT => 'project';
use constant GIT => 'git';
use constant SRC => 'src';

has config => (is => 'ro', required => 1);
has list   => (is => 'lazy');

sub _build_list ($self) {
   my $config = $self->config;

   # first of all check what comes from the configuration (cmdline/env)
   my $bps = $config->{dibspack};
   return [ref $bps ? $bps->@* : $bps] if defined $bps;

   # now check for a .dibspacks in the source directory
   my $src_dir = path($config->{project_dir})->absolute
      ->child($config->{project_src_dir});
   my $dbs_path = $src_dir->child('.dibspacks');
   ouch 400, 'no dibspack specified' unless $dbs_path->exists;

   # if a plain file, just take whatever it's written inside
   return [$dbs_path->lines_utf8({chomp => 1})] if $dbs_path->is_file;

   # in this case, paths have to be forced as starting with src, literally
   my $csd = path(SRC);
   return [map {$csd->child($_->relative($src_dir))} $dbs_path->children];
}

sub fetch ($self) { map { $self->_fetch_urish($_) } $self->list->@* }

sub _fetch_urish ($self, $urish) {
   ouch 'invalid empty URI(sh)' unless defined($urish) && length($urish);

   return $self->_project_dibspack($urish, $self->_fetch_uri($urish))
      if $urish =~ m{\A (?: http s? | git | ssh ) :// }imxs;

   my $path = path($urish);
   return $path->stringify if $path->is_absolute; # exp. in "from" image

   my ($first, $subpath) = __split_first_directory($path);
   return $self->_project_dibspack($urish, $subpath) if $first eq PROJECT;
   return $self->_src_dibspack($urish, $subpath)     if $first eq SRC;
   ouch 400, "unsupported dibspack $urish";
}

sub _fetch_uri ($self, $uri) {
   require Digest::MD5;
   my $name = Digest::MD5::md5_hex($uri);

   my $config = $self->config;
   my ($pd, $pdd) = $config->@{qw< project_dir project_dibspacks_dir >};
   require Dibs::Git;
   Dibs::Git::fetch($uri, path($pd)->child($pdd, GIT, $name));

   return path(GIT, $name);
}

sub _assert_dibspack ($self, $urish, $path) {
   my $bin_dir = path($path)->child(BIN);
   ouch 400, "invalid dibspack $urish" unless $bin_dir->is_dir;
   for my $name (qw< build-detect build bundle-detect bundle >) {
      ouch 400, "missing $name in dibspack $urish"
         unless $bin_dir->child($name)->is_file;
   }
   return;
}

sub _resolve_dibspack ($self, $urish, $path, $base_host, $base_container) {
   my $config      = $self->config;
   my $project_dir = path($config->{project_dir});
   my $host_path   = $project_dir->child($config->{$base_host}, $path);
   $self->_assert_dibspack($urish, $host_path);
   return path($config->{$base_container}, $path);
}

sub _project_dibspack ($self, @args) {
   return $self->_resolve_dibspack(@args,
     qw< project_dibspacks_dir container_dibspacks_dir >);
}

sub _src_dibspack ($self, @args) {
   return $self->_resolve_dibspack(@args,
     qw< project_src_dir       container_src_dir >);
}

sub __split_first_directory ($path) {
   my $root = Path::Tiny->rootdir;
   my $abs = $path->absolute($root);
   $abs = $abs->parent while ! $abs->parent->is_rootdir;
   my $first = $abs->relative($root)->stringify;
   return ($first, $path->relative($first));
}

1;
__END__


