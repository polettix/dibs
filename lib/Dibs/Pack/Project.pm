package Dibs::Pack::Project;
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
   my %spec = ref($args) ? $args->%* : (path => $args);
   my $path = delete $spec{path};
   ouch 400, 'no path' unless length($path // '');
   $spec{id} = PROJECT . ':' . $path;
   $spec{name} //= $spec{id};
   $spec{host_path} = $dibs->resolve_project_path(DIBSPACKS, $path);
   $spec{container_path} = $dibs->resolve_container_path(DIBSPACKS, $path);
   return \%spec;
}

1;
__END__
