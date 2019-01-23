package Dibs::Fetcher::Http;
use 5.024;
use Ouch ':trytiny_var';
use Moo;
use Log::Any qw< $log >;
use Path::Tiny ();
use Digest::MD5 qw< md5_hex >;
use Dibs::Output;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Fetcher';

has URI => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   my $uri = $spec{URI} // $spec{raw};
   ouch 400, 'no URI provided' unless length($uri // '');

   return {URI => $uri};
}

sub id ($self) { return md5_hex($self->URI) }

sub materialize_in ($self, $location) {
   my $uri = $self->URI;
   my $local_target = $location->host_path;
   OUTPUT "http: $uri -> $local_target";
   require HTTP::Tiny;
   my $response = HTTP::Tiny->new->get($uri);
   ouch 500, $response->{content} if $response->{status} == 599;
   ouch 400, "HTTP($response->{status}): $response->{content}"
      unless $response->{success};
   $local_target->parent->mkpath;
   $local_target->spew_raw($response->{content});
   return;
}

1;
__END__
