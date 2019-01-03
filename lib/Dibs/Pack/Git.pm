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
has _full_orig => (is => 'lazy');
has origin     => (is => 'ro', required => 1);
has '+path'    => (default => sub { OPERATE });
has ref        => (is => 'ro', default => sub { return undef });

sub BUILDARGS ($class, $args, $dibs) {
   my %spec = ref($args) ? $args->%* : (origin => $args);

   my $origin = $spec{origin};
   ouch 400, 'no origin provided' unless length($origin // '');

   $spec{name} //= $origin;

   if ($origin =~ m{\#}mxs) {
      ouch 400, 'cannot specify ref and fragment in URL'
         if length($spec{ref} // '');
      @spec{qw< origin ref >} = split m{\#}mxs, $origin, 2;
      $origin = $spec{origin};
   }

   delete $spec{ref} unless length($spec{ref} // '');

   my $path = Path::Tiny::path(GIT, md5_hex($origin));
   $spec{host_path} = $dibs->resolve_project_path(DIBSPACKS, $path);
   $spec{container_path} = $dibs->resolve_container_path(DIBSPACKS, $path);
   
   return \%spec;
}

sub materialize ($self) {
   Dibs::Git::fetch($self->_full_orig, $self->host_path);
}

around resolve_paths => sub ($super, $self, $path) {
   return $self->$super($path // $self->path // OPERATE);
};

sub _build__full_orig ($self) {
   my $ref = $self->ref;
   return $self->origin unless length($ref // '');
   return $self->origin . '#' . $ref;
}

sub _build_id ($self) { return GIT . ':' . $self->_full_orig }

1;
__END__
