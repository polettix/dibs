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

use constant SRC => 'src';

has moniker => (is => 'ro', required => 1);
has _list => (is => 'ro', required => 1);
sub list ($self) { return $self->_list->@* }

sub BUILDARGS ($class, $m, $c) {
   my @l = map {Dibs::Pack->create($c, $_)} __build_list($c, $m);
   return { moniker => $m, _list => \@l };
}

sub __build_list($config, $what) {
   # first of all check what comes from the configuration
   my $ds = $config->{definitions}{$what}{dibspacks};
   return (ref $ds ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibspacks in the source directory
   my $project_dir = path($config->{project_dir})->absolute;
   my $src_dir     = $project_dir->child($config->{project_src_dir});
   my $ds_path     = $src_dir->child('.dibspacks');

   # if the file does not exist we just give up
   if (! $ds_path->exists) {
      $log->warning("no dibspack found for $what");
      return;
   }

   # if a plain file, just take whatever it's written inside
   return $ds_path->lines_utf8({chomp => 1}) if $ds_path->is_file;

   # in this case, paths have to be forced as starting with SRC
   my $csd = path(SRC); # helper to have stuff "inside" SRC
   return map {
      my $rel_path = $_->relative($src_dir);
      $csd->child($rel_path)
   } $ds_path->child($what)->children;
}

1;
__END__
