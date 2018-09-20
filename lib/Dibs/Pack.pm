package Dibs::Pack;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny qw< path >;
use List::Util qw< any >;
use Try::Catch;
use Module::Runtime qw< use_module >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< :constants :functions >;

has container_path => (coerce => \&_path, is => 'ro', required => 1);
has host_path      => (coerce => \&_path, is => 'ro', required => 1);
has id             => (is => 'lazy');
has name           => (is => 'ro', required => 1);

sub _build_id ($self) {
   our $__id //= 0;
   return ++$__id;
}

sub _path ($p) { defined($p) ? path($p) : undef }

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub create ($pkg, $sp, $dibs) {
   my ($raw, %args) = ref($sp) eq 'HASH' ? (undef, $sp->%*) : $sp->@*;
   $pkg->expand_dwim(\%args) unless defined $raw;
   my $type = delete $args{type};
   my $class = delete($args{class}) // $pkg->class_for($type);
   return $class->new($raw // \%args, $dibs);
}

sub expand_dwim ($pkg, $args) {
   if (exists($args->{run}) && !exists($args->{type})) {
      $args->{type}    = IMMEDIATE,
      $args->{program} = delete $args->{run};
   }
   return $args;
}

sub resolve_paths ($self, $path = undef) {
   return map {
      my $p = $self->$_;
      $p = $p->child($path) if defined $path;
      ($_ => $p);
   } qw< container_path host_path >;
}

sub type ($self) { return lc((ref($self) || $self) =~ s{.*::}{}mxsr) }

1;
__END__
