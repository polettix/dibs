package Dibs::Get;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use Dibs::Run qw< assert_command >;
no warnings qw< experimental::postderef experimental::signatures >;

sub get_origin ($source, $target) {
   ouch 500, "target directory $target exists" if path($target)->exists;
   my ($type, $location) = $source =~ m{
      \A (git|dir) \@ (.*) \z }mxs;
   ($type, $location) = (git => $source) unless defined $location;
   my $callback = __PACKAGE__->can("_get_origin_$type")
      or ouch 400, "unknown source type $type";
   return $callback->($location, $target);
}

sub _get_origin_git ($uri, $target) {
   my ($origin, $ref) = split m{\#}mxs, $uri;
   require Dibs::Git;
   Dibs::Git::clone($uri, $target);
   Dibs::Git::checkout_ref($target, $ref) if length($ref // '');
   return;
}

sub _get_origin_dir ($path, $target) {
   $path->is_dir or ouch 400, "origin directory $path does not exist";
   assert_command(qw< cp -a >, path($path)->stringify,
      path($target)->stringify);
   return;
}

1;
__END__
