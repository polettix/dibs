package Dibs::Pack::Git;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch;
use Moo;
use Path::Tiny;
use Digest::MD5 qw< md5_hex >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Dibs::Git;

extends 'Dibs::Pack';
has origin  => (is => 'ro', required => 1);
has subpath => (is => 'ro', default => '');
has ref     => (is => 'ro', required => 1);

sub BUILDARGS ($class, $config, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   my $origin = $spec{origin};
   ouch 400, 'no origin provided' unless length($origin // '');

   if (! defined $spec{name}) {
      $spec{name} = $origin;
      $spec{name} .= " -> $spec{subpath}" if length($spec{subpath} // '');
   }

   if ($origin =~ m{\#}mxs) {
      ouch 400, 'cannot specify ref and fragment in URL'
         if length($spec{ref} // '');
      @spec{qw< origin ref >} = split m{\#}mxs, $origin, 2;
      $origin = $spec{origin};
   }

   $spec{ref} = 'master' unless length($spec{ref} // '');
   
   my $path = path(GIT, md5_hex($origin));
   $spec{host_path} = $class->resolve_host_path($config, DIBSPACKS, $path);
   $path = $path->child($spec{subpath}) if length($spec{subpath} //= '');
   $spec{container_path} =
      $class->resolve_container_path($config, DIBSPACKS, $path);

   return \%spec;
}

sub parse_new ($class, $config, $origin, $full_spec = undef) {
   return $class->new($config, origin => $origin);
}

sub fetch ($self) {
   Dibs::Git::fetch($self->origin, $self->host_path);
}

1;
__END__

