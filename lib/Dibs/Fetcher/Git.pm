package Dibs::Fetcher::Git;
use 5.024;
use Ouch;
use Moo;
use Log::Any qw< $log >;
use Path::Tiny ();
use Digest::MD5 qw< md5_hex >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Fetcher::Role';

has origin     => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   my $origin = $spec{origin} // $spec{raw};
   ouch 400, 'no origin provided' unless length($origin // '');

   if (length(my $ref = $spec{ref} // '')) {
      ouch 400, 'cannot specify ref and fragment in URL'
         if $origin =~ m{\#}mxs;
      $origin .= '#' . $ref;
   }

   return {origin => $origin};
}

sub id ($self) { return md5_hex($self->origin) }

sub materialize_in ($self, $location) {
   require Dibs::Git;
   Dibs::Git::fetch($self->origin, $location->host_path);
   return;
}

1;
__END__
