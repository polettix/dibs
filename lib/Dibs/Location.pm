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

sub clone_with ($s, %args) {
   for my $field (qw< base path zone >) {
      next if exists $args{$field};
      $args{$field} = $s->$field();
   }
   return ref($s)->new(%args);
}

sub container_path ($s, @p) { $s->_path($s->zone->container_base, @p) }
sub host_path ($s, @p) { $s->_path($s->zone->host_base, @p) }

sub _path ($self, $zbase, @subpath) {
   return undef unless defined $zbase;
   pop @subpath if @subpath && ! defined($subpath[-1]);
   @subpath = $self->path if (!@subpath) && defined($self->path);
   unshift @subpath, $self->base if defined($self->base);
   return scalar(@subpath) ? $zbase->child(@subpath) : $zbase;
} ## end sub _path

sub sublocation ($self, @sp) {
   my $base = $self->base;
   my $subb = defined $base ? $base->child(@sp) : Path::Tiny::path(@sp);
   return ref($self)->new(
      base => $subb,
      path => undef,
      zone => $self->zone,
   );
}

sub _topath ($p) { defined($p) ? Path::Tiny::path($p) : undef }

1;
__END__
