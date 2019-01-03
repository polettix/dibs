package Dibs::Resource;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny ();
use List::Util qw< any >;
use Try::Catch;
use Module::Runtime qw< use_module >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< :constants :functions >;

has id       => (is => 'lazy');
has is_materialized => (is => 'rw', init_arg => 'missing', default => 0);
has location => (is => 'ro', required => 1);
has name     => (is => 'ro', required => 1);

sub _build_id ($self) {
   our $__id //= 0;
   return ++$__id;
}

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub create ($pkg, $sp, $dibs) {
   my $ref = ref $sp;
   my ($raw, %args) = 
        $ref eq 'HASH'  ? (undef, $sp->%*)
      : $ref eq 'ARRAY' ? ($sp->@*)
      :                   $pkg->parse($sp);
   $pkg->expand_dwim(\%args) unless defined $raw;
   my $type = delete $args{type};
   my $class = delete($args{class}) // $pkg->class_for($type);
   return $class->create($raw // \%args, $dibs);
}

sub expand_dwim ($pkg, $args) {
   if (exists($args->{run}) && !exists($args->{type})) {
      $args->{type}    = IMMEDIATE,
      $args->{program} = delete $args->{run};
   }
   return $args;
}

sub materialize ($self) { return $self->is_materialized(1) }

sub parse ($self, $sp) {
   return ($sp, type => GIT)  if $sp =~ m{\A git://}mxs;
   return ($sp, type => HTTP) if $sp =~ m{\A http://}mxs;
   my ($type, $raw) = split m{:}mxs, $sp, 2;
   return ($raw, type => $type);
}

sub type ($self) { return lc((ref($self) || $self) =~ s{.*::}{}mxsr) }

1;
__END__
