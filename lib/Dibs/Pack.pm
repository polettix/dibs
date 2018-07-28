package Dibs::Pack;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny qw< path >;
use List::Util qw< any >;
use Try::Catch;
use Module::Runtime qw< use_module >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< :constants :functions >;

has name           => (is => 'ro', required => 1);
has env            => (is => 'ro', default => sub { return {} });
has indent         => (is => 'ro', default => sub { return 42 });
has _args          => (
   is => 'ro',
   default => sub { return [] },
   init_arg => 'args',
);
has _detect_args   => (
   is => 'ro',
   default => sub { return [] },
   init_arg => 'detect_args',
);
has host_path      => (is => 'ro', required => 1);
has container_path => (is => 'ro', required => 1);

sub _build_name ($self) { return $self->origin }

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub do_detect   ($self) { return scalar($self->_detect_args->@*) }
sub args        ($self) { return $self->_args->@* }
sub detect_args ($self) { return $self->_detect_args->@* }

sub create ($pkg, $config, $spec) {
   my ($class, $args);
   if (my $sref = ref $spec) {
      ouch 400, "invalid reference of type '$sref' for dibspack"
         unless $sref eq 'HASH';
      $args = {$spec->%*};
   }
   else {
      my ($type, $data) = 
         ($spec =~ m{\A (?: http s? | git | ssh ) :// }imxs)
         ? (git => $spec) : split(m{:}mxs, $spec, 2);
      $class = $pkg->class_for($type);
      $args = $class->parse_specification($data, $config);
   }
   $args = $pkg->integrate_and_validate($args, $config);
   $class //= $pkg->class_for(delete $args->{type});
   return $class->new($config, $args);
}

sub merge_defaults ($pkg, $args, $config) {
   my %args = $args->%*;
   my @candidates = (delete $args{default}, '*');
   my $cdefs = $config->{defaults}{dibspack} // {};
   while (@candidates) {
      defined(my $candidate = shift @candidates) or next;
      if (ref($candidate) eq 'ARRAY') {
         unshift @candidates, $candidate->@*;
         next;
      }
      next unless $cdefs->{$candidate};
      %args = ($cdefs->{$candidate}->%*, %args);
   }
   return \%args;
}

sub integrate_and_validate ($pkg, $as, $config) {
   $as = $pkg->merge_defaults($as, $config);
   defined($as->{indent} = yaml_boolean($as->{indent} // 'Y'))
      or ouch 400, '`indent` in dibspack MUST be a YAML boolean';
   defined($as->{skip_detect} = yaml_boolean($as->{skip_detect} // 'N'))
      or ouch 400, '`skip_detect` in dibspack MUST be a YAML boolean';
   return $as;
}

sub BUILDARGS ($class, @args) {
   use Data::Dumper; $log->info(Dumper \@args); exit 0;
}

sub resolve_host_path ($class, $config, $zone, $path) {
   my $pd = path($config->{project_dir})->absolute;
   $log->debug("project dir $pd");
   my $zd = $config->{project_dirs}{$zone};
   $log->debug("zone <$zd> path<$path>");
   return $pd->child($zd, $path)->stringify;
}

sub resolve_container_path ($class, $config, $zone, $path) {
   return path($config->{container_dirs}{$zone}, $path)->stringify;
}

sub _create_inside ($package, $config, $specification) {
   return $package->new(
      type => INSIDE,
      specification  => $specification,
      host_path => undef,
      container_path => $specification,
   );
}

sub needs_fetch { return }

sub has_program ($self, $program) {
   return (!defined($self->host_path))
       || -x path($self->host_path, $program)->stringify;
}

1;
__END__
