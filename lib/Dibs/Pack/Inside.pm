package Dibs::Pack::Inside;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';

extends 'Dibs::Pack';

sub BUILDARGS ($class, $args, $dibs) {
   if (ref($args) ne 'HASH') {
      my $type = $class->type;
      ouch 400,
         "dibspack of type '$type' does not accept inline specification";
   }
   my %spec = ref($args) ? $args->%* : (path => $args);
   my $path = delete $spec{path};
   ouch 400, 'no path' unless length($path // '');
   $spec{id} = INSIDE . ':' . $path; # not really important...
   $spec{name} //= $spec{id};
   $spec{host_path} = undef;
   $spec{container_path} = $path;
   return \%spec;
}

around resolve_paths => sub ($super, $self, $path) {
   if (defined $path) { # by default there's no subpath support
      my $type = $self->type;
      ouch 400, "dibspack of type '$type' does not accept paths";
   }
   return $self->$super;
};

1;
__END__
