package Dibs::Zone;
use 5.024;
use experimental qw< postderef signatures >;
use Path::Tiny ();
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

use overload (
   q{""}    => sub { $_[0]->name },
   bool     => sub { 1 },
   fallback => 1,
);

has container_base => (is => 'ro', default => undef, coerce => \&_topath);
has host_base      => (is => 'ro', default => undef, coerce => \&_topath);
has name => (is => 'ro', required => 1);

sub container_path ($self, @p) { $self->_path($self->container_base, @p) }
sub host_path ($self, @p) { $self->_path($self->host_base, @p) }
sub _path ($s, $b, @p) { $b && @p ? $b->child(@p) : $b }
sub _topath ($p) { defined($p) ? Path::Tiny::path($p) : undef }

1;
