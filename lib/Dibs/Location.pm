package Dibs::Location;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny ();
use Try::Catch;
no warnings qw< experimental::postderef experimental::signatures >;

has container_base => (is => 'ro', required => 1, coerce => \&_pathify);
has host_base      => (is => 'ro', required => 1, coerce => \&_pathify);
has path           => (is => 'ro', default => undef);

sub container_path ($self, @subpath) {
   return $self->_path($self->container_base, @subpath);
}

sub host_path ($self, @subpath) {
   return $self->_path($self->host_base, @subpath);
}

sub paths ($self, @subpath) {
   return map { $_ => $self->$_(@subpath) } qw< container_path host_path >;
}

sub _path ($self, $base, @subpath) {
   return undef unless defined $base;
   @subpath = $self->path unless @subpath;
   pop @subpath unless defined $subpath[-1];
   return scalar(@subpath) ? $base->child(@subpath) : $base;
}

sub _pathify ($p) { defined($p) ? Path::Tiny::path($p) : undef }

1;
__END__
