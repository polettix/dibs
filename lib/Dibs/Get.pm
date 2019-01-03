package Dibs::Get;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use Dibs::Run qw< assert_command >;
use Try::Catch;
no warnings qw< experimental::postderef experimental::signatures >;

sub get_origin ($source, $target, $options = {}) {
   $target = path($target);
   if ($target->exists) {
      ouch 500, "target directory $target exists" unless $options->{wipe};
      try { $target->remove_tree({safe => 0}) }
      catch { ouch 500, "cannot delete $target, permissions maybe?" };
   }
   $target = $target->stringify;

   # the definition of the source might be an associative array or a string
   my %source;
   if (ref $source) {
      %source = $source->%*;
   }
   else {
      @source{qw< type location >}
         = $source =~ m{\A (git|dir) \@ (.*) \z}mxs;
      @source{qw< type location >} = (git => $source)
         unless defined $source{location};
   }

   # this is just paranoia, double check that there is something to call
   my $callback = __PACKAGE__->can("_get_origin_$source{type}")
      or ouch 400, "unknown source type $source{type}";
   $callback->($source{location}, $target, $options);

   # change owner if needed. This generally requires using sudo or root
   assert_command(qw< chown -R >, $source{user}, $target)
      if defined $source{user};

   return;
}

sub _get_origin_git ($uri, $target, $options) {
   my ($origin, $ref) = split m{\#}mxs, $uri;
   require Dibs::Git;
   ouch 400, "origin $origin is in a dirty state (see manual for --dirty)"
      if $options->{clean_only} && Dibs::Git::is_dirty($uri);
   Dibs::Git::clone($origin, $target);
   Dibs::Git::checkout_ref($target, $ref) if length($ref // '');
   return;
}

sub _get_origin_dir ($path, $target, $options) {
   $path->is_dir or ouch 400, "origin directory $path does not exist";
   assert_command(qw< cp -a >, path($path)->stringify,
      path($target)->stringify);
   return;
}

1;
__END__
