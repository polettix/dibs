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

sub BUILDARGS ($class, $config, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   ouch 400, 'no program provided' unless defined $spec{program};
   $spec{program} =~ s{^[|]}{}gmxs;
   ouch 400, 'empty program provided' unless length $spec{program};

   my $id = $spec{id} = md5_hex($spec{program});
   $spec{name} //= $id;

   my @as = ($config, DIBSPACKS, Path::Tiny::path(IMMEDIATE, $id));
   $spec{host_path} = $class->resolve_host_path(@as);
   $spec{container_path} = $class->resolve_container_path(@as);

   return \%spec;
}

sub parse_specification {
   ouch 400, 'cannot use inline specification with Immediate dibspacks';
}

sub needs_fetch ($self) { return ! -e $self->host_path }

sub fetch ($self) {
   my $path = Path::Tiny::path($self->host_path);
   $path->parent->mkpath;
   $path->spew_utf8($self->program);
   $path->chmod('a+x');
}


1;
__END__

