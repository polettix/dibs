package Dibs::Pack::Instance;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Scalar::Util 'blessed';
use Dibs::Location;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Identifier';

has _fetcher => (is => 'ro', default => undef, init_arg => 'fetcher');

has location => (
   coerce   => \&__inflate_location,
   is       => 'ro',
   isa      => \&__assert_location,
   required => 1,
);

sub container_path ($s, @p) { $s->location->container_path(@p) }

sub host_path      ($s, @p) { $s->location->host_path(@p) }

sub materialize ($self) {
   my $fetcher = $self->_fetcher or return;
   return $fetcher->($self->location) unless blessed $fetcher;
   $fetcher->materialize_in($self->location);
}

sub __assert_location ($location) {
   return if blessed($location) && $location->isa('Dibs::Location');
   ouch 400, "$location is not a Dibs::Location";
}

sub __inflate_location ($spec) {
   return $spec if blessed($spec) && $spec->isa('Dibs::Location');
   return Dibs::Location->new($spec) if ref($spec) eq 'HASH';
   ouch 400, "invalid location '$spec' for pack";
}

1;
__END__
