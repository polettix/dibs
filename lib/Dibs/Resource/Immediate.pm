package Dibs::Resource::Immediate;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Log::Any qw< $log >;
use Path::Tiny;
use Digest::MD5 qw< md5_hex >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Dibs::Location;

extends 'Dibs::Resource';

has program => (is => 'ro', required => 1);

sub create ($class, $args, $dibs) {
   my %spec = ref($args) ? $args->%* : (program => "#/bin/sh\n$args");
   ouch 400, 'no program provided' unless defined $spec{program};
   ouch 400, 'empty program provided' unless length $spec{program};

   if (defined (my $prefix = delete $spec{prefix})) {
      $prefix = quotemeta $prefix;
      $spec{program} =~ s{^$prefix}{}gmxs;
   }

   my $id = $spec{id} = IMMEDIATE . ':' . md5_hex($spec{program});
   $spec{name} //= $id;

   $spec{location} = Dibs::Location->new(
      container_base => $dibs->resolve_container_path(DIBSPACKS),
      host_base      => $dibs->resolve_project_path(DIBSPACKS),
      path           => path(IMMEDIATE, $id),
   );

   return $class->new(%spec);
}

sub materialize ($self) {
   return if $self->is_materialized;
   my $path = $self->location->host_path;
   $path->parent->mkpath;
   $path->spew_utf8($self->program);
   $path->chmod('a+x');
   return $self->is_materialized(1);
}

1;
__END__

