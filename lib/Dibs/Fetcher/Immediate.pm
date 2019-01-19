package Dibs::Fetcher::Immediate;
use 5.024;
use Ouch;
use Moo;
use Log::Any qw< $log >;
use Path::Tiny ();
use Digest::MD5 qw< md5_hex >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Fetcher';

has program => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %spec = (@args && ref($args[0])) ? $args[0]->%* : @args;

   my $program = $spec{run} // $spec{program};
   ouch 400, 'no program provided' unless defined $program;
   ouch 400, 'empty program provided' unless length $program;

   if (defined (my $prefix = delete $spec{prefix})) {
      $prefix = quotemeta $prefix;
      $program =~ s{^$prefix}{}gmxs;
   }

   return {program => $program};
}

sub id ($self) { return md5_hex($self->program) }

sub materialize_in ($self, $location) {
   my $path = $location->host_path;
   $path->parent->mkpath;
   $path->spew_utf8($self->program);
   $path->chmod('a+x');
   return;
}

1;
__END__

