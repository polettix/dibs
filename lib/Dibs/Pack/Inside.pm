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

sub BUILDARGS ($class, $config, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;
   my $path = delete $spec{path};
   ouch 400, 'no path' unless length($path // '');
   $spec{name} //= INSIDE . ':' . $path;
   $spec{host_path} = undef;
   $spec{container_path} = $path;
   return \%spec;
}

sub parse_specification ($class, $path, @rest) { return {path => $path} }

1;
__END__
