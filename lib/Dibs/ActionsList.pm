package Dibs::ActionsList;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path >;
use Dibs::Action;
use Dibs::Config ':constants';
use YAML::XS 'LoadFile';
use Scalar::Util qw< refaddr >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($dibs, $step) {
   map {Dibs::Action->create($_, $dibs)}
      __flatten_list($step, {}, __build_list($step, $dibs));
}

sub __flatten_list ($step, $flags, @input) {
   map {
      if (ref($_) eq 'ARRAY') {
         my $addr = refaddr($_);
         ouch 400, "circular reference in actions for $step"
            if $flags->{$addr}++;
         __flatten_list($step, $flags, $_->@*);
         delete $flags->{$addr};
      }
      else { $_ }
   } @input;
}

sub __build_list ($step, $dibs) {
   # first of all check what comes from the configuration
   my $ds = $dibs->dconfig($step => 'actions');
   return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibsactions in the source directory
   my $src_dir = $dibs->resolve_project_path(SRC);
   my $ds_path = $src_dir->child(DPFILE);

   # if a plain file, just take whatever is written inside
   if ($ds_path->is_file) {
      $ds = LoadFile($ds_path->stringify)->{$step};
      return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds);
   }

   # if dir, iterate over its contents
   if ($ds_path->child($step)->is_dir) {
      return  map {
         my $child = $_;
         my $bn = $child->basename;
         next if ($bn eq '_') || (substr($bn, 0, 1) eq '.');
         $child->child(OPERATE) if $child->is_dir;
         next unless $child->is_file && -x $child;
         {
            type => SRC,
            path => $child->relative($src_dir),
         };
      } sort { $a cmp $b } $ds_path->child($step)->children;
   }

   ouch 400, "no actions found for step $step";
   return; # unreached
}

1;
__END__
