package Dibs::Location;
use 5.024;
use experimental qw< postderef signatures >;
use Path::Tiny ();
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< blessed >;
use Dibs::Zone;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

has base => (is => 'ro', default => undef, coerce => \&_topath);
has path => (is => 'ro', default => undef, coerce => \&_topath);
has zone => (
   is       => 'ro',
   required => 1,
   isa      => sub {
      ouch 500, 'zone must be a Dibs::Zone'
        unless blessed($_[0]) && $_[0]->isa('Dibs::Zone');
   },
   coerce => sub {
      return $_[0] if blessed($_[0]) && $_[0]->isa('Dibs::Zone');
      return Dibs::Zone->new($_[0]) if ref($_[0]) eq 'HASH';
      return $_[0];    # isa will complain
   },
);

sub clone_in ($self, $zone) {
   return $self->new(
      base => $self->base,
      path => $self->path,
      zone => $zone
   );
} ## end sub clone_in

sub container_path ($s, @p) { $s->_path($s->zone->container_base, @p) }
sub host_path ($s, @p) { $s->_path($s->zone->host_base, @p) }

sub _path ($self, $zbase, @subpath) {
   return undef unless defined $zbase;
   unshift @subpath, $self->base if defined($self->base);
   @subpath = $self->path unless @subpath;
   pop @subpath unless defined $subpath[-1];
   return scalar(@subpath) ? $zbase->child(@subpath) : $zbase;
} ## end sub _path

sub _topath ($p) { defined($p) ? Path::Tiny::path($p) : undef }

1;
__END__
