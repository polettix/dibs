package Dibs::PacksList;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Moo;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path >;
use Dibs::Pack;
no warnings qw< experimental::postderef experimental::signatures >;

use constant BIN => 'bin';
use constant PROJECT => 'project';
use constant GIT => 'git';
use constant SRC => 'src';

has _for_build  => (is => 'ro', required => 1);
has _for_bundle => (is => 'ro', required => 1);

sub for_build  ($self) { $self->_for_build->@*  }
sub for_bundle ($self) { $self->_for_bundle->@* }

sub list_for ($self, $what) {
   return $self->for_build if $what eq 'build';
   return $self->for_bundle if $what eq 'bundle';
   ouch 400, "unknown list type $what";
}

sub create ($package, $config) {
   my $for_build  = __aref_for($config, 'build');
   my $for_bundle = __aref_for($config, 'bundle');
   return $package->new(
      _for_build  => $for_build,
      _for_bundle => $for_bundle,
   );
}

sub __aref_for ($config, $what) {
   # first of all check what comes from the configuration
   my $ds = $config->{$what}{dibspacks};
   return __aref($config, ref $ds ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibspacks in the source directory
   my $src_dir = path($config->{project_dir})->absolute
      ->child($config->{project_src_dir});
   my $ds_path = $src_dir->child('.dibspacks');
   ouch 400, 'no dibspack specified' unless $ds_path->exists;

   # if a plain file, just take whatever it's written inside
   return __aref($config, $ds_path->lines_utf8({chomp => 1}))
      if $ds_path->is_file;

   # in this case, paths have to be forced as starting with src, literally
   my $csd = path(SRC);
   return __aref($config,
      map {$csd->child($_->relative($src_dir))} $ds_path->child($what)->children);
}

sub __aref ($c, @s) { [map { Dibs::Pack->create($c, $_) } @s] }

1;
__END__
