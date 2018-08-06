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
   coerce   => \&__parse_args,
   default  => sub { return [] },
   init_arg => 'args',
   is       => 'ro',
);
has host_path      => (is => 'ro', required => 1);
has container_path => (is => 'ro', required => 1);

has id => (is => 'lazy');
has user => (is => 'ro', default => sub { return });

sub docker_run_args ($self) {
   my @retval = (
      indent => $self->indent,
   );
   push @retval, user => $self->user if defined $self->user;
   return @retval;
}

sub _build_id ($self) {
   our $__id //= 0;
   return ++$__id;
}

sub class_for ($package, $type) {
   ouch 400, 'undefined type for dibspack' unless defined $type;
   return try { use_module($package . '::' . ucfirst(lc($type))) }
          catch { ouch 400, "invalid type '$type' for dibspack ($_)" }
}

sub args ($self) { return $self->_args->@* }

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
   $args = $pkg->validate($pkg->merge_defaults($args, $config));
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

sub validate ($pkg, $as) {
   defined($as->{indent} = yaml_boolean($as->{indent} // 'Y'))
      or ouch 400, '`indent` in dibspack MUST be a YAML boolean';
   return $as;
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

sub needs_fetch { return }

sub has_program ($self, $program) {
   return (!defined($self->host_path))
       || -x path($self->host_path, $program)->stringify;
}

sub __parse_args ($value) {
   return $value if ref $value;

   $value =~ s{\\\n}{}gmxs;
   $value =~ s{\A\s+|\s*\z}{ }gmxs;
   my ($in_single, $in_double, $is_escaped, $is_function, @args, $buffer);
   for my $c (split m{}mxs, $value) {
      if ($is_escaped) {
         $is_escaped = 0;
      }
      elsif ($in_single) {
         next unless $in_single = ($c ne "'");
         # otherwise just get the char
      }
      elsif ($c eq '\\') { # escape can happen in plain or dquote
         $is_escaped = 1;
         next; # ignore escape char
      }
      elsif ($in_double) {
         next unless $in_double = ($c ne '"');
         # otherwise just get the char
      }
      elsif ($c =~ m{\s}mxs) {
         if (defined $buffer) {
            push @args,
               $is_function
               ? { split m{:}mxs, substr($buffer, 1), 2 }
               : $buffer;
         }
         ($buffer, $is_function) = ();
         next; # remove spacing chars
      }
      elsif ($c eq "'") {
         $in_single = 1;
         next; # ignore quote char
      }
      elsif ($c eq '"') {
         $in_double = 1;
         next; # ignore quote char
      }
      elsif ($c eq '@' && ! defined($buffer)) {
         $is_function = 1;
      }
      ($buffer //= '') .= $c;
   }

   ouch 400, 'missing closing single quote' if $in_single;
   ouch 400, 'missing closing double quote' if $in_double;
   ouch 400, 'stray escape character at end' if $is_escaped;
   return \@args;
}

1;
__END__
