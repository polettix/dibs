package Dibs::Pack::Immediate;
use 5.024;
use Ouch;
use Moo;
use Log::Any qw< $log >;
use Path::Tiny ();
use Digest::MD5 qw< md5_hex >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';

extends 'Dibs::Pack';

has program => (is => 'ro', required => 1);

sub BUILDARGS ($class, $args, $dibs) {
   my %spec = $args->%*;

   ouch 400, 'no program provided' unless defined $spec{program};
   ouch 400, 'empty program provided' unless length $spec{program};

   if (defined (my $prefix = delete $spec{prefix})) {
      $prefix = quotemeta $prefix;
      $spec{program} =~ s{^$prefix}{}gmxs;
   }

   my $id = $spec{id} = IMMEDIATE . ':' . md5_hex($spec{program});
   $spec{name} //= $id;

   my $path = Path::Tiny::path(IMMEDIATE, $id);
   $spec{host_path} = $dibs->resolve_project_path(DIBSPACKS, $path);
   $spec{container_path} = $dibs->resolve_container_path(DIBSPACKS, $path);

   return \%spec;
}

sub materialize ($self) {
   my $path = Path::Tiny::path($self->host_path);
   $path->parent->mkpath;
   $path->spew_utf8($self->program);
   $path->chmod('a+x');
   return;
}

1;
__END__

