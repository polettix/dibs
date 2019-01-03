package Dibs::Action;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'id',                #
   'container_path',    #
   'name',              #
   'run',               #
);

1;
__END__


package Dibs::Action;
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

has _args          => (
   coerce   => \&__parse_args,
   default  => sub { return [] },
   init_arg => 'args',
   is       => 'ro',
);
has container_path => (is => 'ro', required => 1);
has env            => (is => 'ro', default => sub { return {} });
has envile         => (is => 'ro', default => sub { return {} });
has host_path      => (is => 'ro', required => 1);
has indent         => (is => 'ro', default => sub { return 42 });
has name           => (is => 'ro', required => 1);
has user           => (is => 'ro', default => sub { return });

sub args ($self) { return $self->_args->@* }

sub docker_run_args ($self) {
   my @retval = (
      indent => $self->indent,
   );
   push @retval, user => $self->user if defined $self->user;
   return @retval;
}

sub create ($pkg, $spec, $dibs) {
   my $args;
   ouch 400, 'invalid undefined action' unless defined $spec;
   my $sref = ref $spec;
   ouch 400, 'invalid empty action' unless ($sref || length($spec));
   if ($sref) {
      ouch 400, "invalid reference of type '$sref' for action"
         unless $sref eq 'HASH';
      $args = {$spec->%*};
   }
   elsif (substr($spec, 0, 1) eq '/') {
      $args = {
         dibspack => {
            type => INSIDE,
            path => $spec,
         }
      };
   }
   else {
      my ($type, $data) = 
         ($spec =~ m{\A (?: http s? | git | ssh ) :// }imxs)
         ? (git => $spec) : split(m{:}mxs, $spec, 2);
      $args = { dibspack => [$data, type => $type] };
   }
   my $dibspack_spec = delete($args->{dibspack}) //
      {
         type => IMMEDIATE,
         program => scalar(delete($args->{run})),
      };
   my $dibspack = $dibs->dibspack_for($dibspack_spec);
   my $path = delete($args->{path}) // $dibspack->path;
   my $name = delete($args->{name});
   if (! defined($name)) {
      $name = $dibspack->name;
      $name .= " -> $path" if defined $path;
   }
   return $pkg->new(
      $args->%*, # env, envile, ...
      name => $name,
      $dibspack->resolve_paths($path), # returns key-value pairs
   );
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
