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
use Dibs::Config ':constants';
use YAML::Tiny 'LoadFile';
no warnings qw< experimental::postderef experimental::signatures >;

has moniker => (is => 'ro', required => 1);
has _list => (is => 'ro', required => 1);
sub list ($self) { return $self->_list->@* }

sub BUILDARGS ($class, $m, $c) {
   use Data::Dumper; $log->debug(Dumper $c);
   my @l = map {Dibs::Pack->create($c, $_)} __build_list($c, $m);
   return { moniker => $m, _list => \@l };
}

sub __build_list($config, $what) {
   # first of all check what comes from the configuration
   my $ds = $config->{definitions}{$what}{dibspacks};
   return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibspacks in the source directory
   my $project_dir = path($config->{project_dir})->absolute;
   my $src_dir     = $project_dir->child($config->{project_dirs}{&SRC});
   my $ds_path     = $src_dir->child(DPFILE);

   # if a plain file, just take whatever it's written inside
   if ($ds_path->is_file) {
      my $ds = LoadFile($ds_path->stringify)->{$what};
      return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) if defined $ds;
   }

   # if dir, we allow for one single dibspack per "$what", if any
   if ($ds_path->child($what)->is_dir) {
      return  map {
         next unless $_->is_dir;
         my $bn = $_->basename;
         next if ($bn eq '_') || (substr($bn, 0, 1) eq '.');
         SRC . ':' . $_->relative($src_dir);
      } $ds_path->child($what)->children;
   }

   ouch 400, "no dibspack found for step $what";
   return; # unreached
}

1;
__END__
