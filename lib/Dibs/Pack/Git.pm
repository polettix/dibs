package Dibs::Pack::Git;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch;
use Moo;
use Log::Any qw< $log >;
use Path::Tiny ();
use Digest::MD5 qw< md5_hex >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Dibs::Git;

extends 'Dibs::Pack';
has origin     => (is => 'ro', required => 1);
has _full_orig => (is => 'lazy');
has local_path => (is => 'ro', required => 1);
has path       => (is => 'ro', default => 'operate');
has ref        => (is => 'ro', required => 1);
has fetched    => (is => 'rw', default => 0);

sub BUILDARGS ($class, $config, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   my $origin = $spec{origin};
   ouch 400, 'no origin provided' unless length($origin // '');

   if (! defined $spec{name}) {
      $spec{name} = $origin;
      $spec{name} .= " -> $spec{path}" if length($spec{path} // '');
   }

   if ($origin =~ m{\#}mxs) {
      ouch 400, 'cannot specify ref and fragment in URL'
         if length($spec{ref} // '');
      @spec{qw< origin ref >} = split m{\#}mxs, $origin, 2;
      $origin = $spec{origin};
   }

   $spec{ref} = 'master' unless length($spec{ref} // '');
   
   my $p = Path::Tiny::path(GIT, md5_hex($origin));
   $spec{local_path} = $class->resolve_host_path($config, DIBSPACKS, $p);
   $p = $p->child($spec{path}) if length($spec{path} //= '');
   $spec{host_path} = $class->resolve_host_path($config, DIBSPACKS, $p);
   $spec{container_path} =
      $class->resolve_container_path($config, DIBSPACKS, $p);

   return \%spec;
}

sub parse_specification ($c, $origin, @rest) { return {origin => $origin} }

sub needs_fetch ($self) { return ! $self->fetched }

sub fetch ($self) {
   Dibs::Git::fetch($self->_full_orig, $self->local_path);
   $self->fetched(1);
}

sub _build__full_orig ($self) {
   my $ref = $self->ref // '';
   return $self->origin unless length $ref;
   return $self->origin . '#' . $ref;
}

sub _build_id ($self) { return $self->_full_orig }

1;
__END__
