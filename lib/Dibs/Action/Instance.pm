package Dibs::Action::Instance;
use 5.024;
use Ouch ':trytiny_var';
use Log::Any '$log';
use Guard;
use Dibs::Output;
use Dibs::Docker qw< docker_rm docker_run >;
use Dibs::Config ':constants';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Identifier';
with 'Dibs::Role::EnvCarrier';

has args => (is => 'ro', default => sub { return [] });
has dibspack => (is => 'ro', required => 1);
has path => (is => 'ro', default => undef);
has zone_factory => (is => 'ro', required => 1);
has user => (is => 'ro', default => undef);
has indent => (is => 'ro', default => 42);

sub _container_path ($self, @args) { $self->_resolve_path(@args) }
sub _host_path      ($self, @args) { $self->_resolve_path(@args) }
sub _location ($self) {
   my @allowed_zones = $self->zones_factory->items('dibspacks_host');
   return $self->dibspack->location(@allowed_zones);
}

sub _resolve_path ($self, @subpath) {
   @subpath = $self->path if (!@subpath) && defined($self->path);
   my $method = $self->can((caller 1) =~ s{.*::_}{}rmxs);
   return $self->_location->$method(@subpath);
}

sub run ($self, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   ARROW_OUTPUT('+', 'action ' . $self->name);

   %args = (%args, $self->_coalesce_envs(\%args));
   my $p = $self->_container_path;
   my ($exitcode, $cid, $out);

   my $enviles = $self->_write_enviles($args{envile});
   my $envile_zone = $self->zone_factory->item(ENVILE);
   scope_guard { $enviles->remove_tree({safe => 0}) if $enviles };

   return docker_run(
      %args,
      $self->_docker_run_args,

      # overriding everything above
      keep    => 1,
      volumes => $args{volumes},
      workdir => $envile_zone->container_base,
      command => [$p, $self->_command_args(\%args)]
   );
}

sub _command_args ($self, $args) {
   map {
      my $ref = ref $_;
      if ($ref eq 'HASH') {
         my %data = $_->%*;
         my ($type, $data) =
           (scalar(keys %data) == 1)
           ? %data
           : (delete $data{type}, \%data);
         ouch 400, 'unknown type for arg of dibspack' unless defined $type;
         ($type, $data) = ($data, undef) if $type eq 'type';
         if (my ($ptype) = $type =~ m{\A path_ (.+) \z}mxs) {
            $type = 'path';
            $data = {$ptype => $data};
         }
         if ($type eq 'path') {
            ouch 400, 'unrecognized request for path resolution'
              unless (ref($data) eq 'HASH')
              && (scalar(keys $data->%*) == 1);
            my ($name, $path) = $data->%*;
            $self->zone_factory->item($name)->container_path($path);
         } ## end if ($type eq 'path')
         elsif ($type eq 'process_id') { $args->{process}->id }
         elsif ($type eq 'process_name') { $args->{process}->name }
         else {
            ouch 400, "unrecognized arg for dibspack (type: $type)";
         }
      } ## end if ($ref eq 'HASH')
      elsif (!$ref) {
         $_;
      }
      else {
         ouch 400, "invalid arg for dibspack (ref: $ref)";
      }
   } $self->args->@*;
} ## end sub expand_command_args

sub _docker_run_args ($self) {
   my @retval = (
      indent => $self->indent,
   );
   push @retval, user => $self->user if defined $self->user;
   return @retval;
}

sub _coalesce_envs ($self, $args) {
   my @carriers = (
      # $self is considered implicitly by merge_envs/merge_enviles
      $args->{process},
      $self->dibspack,
      ($args->{env_carriers} // [])->@*
   );
   return (
      env    => $self->merge_envs(@carriers),
      envile => $self->merge_enviles(@carriers),
   );
}

sub _write_enviles ($self, $spec) {
   my $env_dir = $self->zone_factory->item(ENVILE)->host_path;
   if ($env_dir->exists && !$env_dir->is_dir) {
      if ($env_dir->is_dir) {
         $env_dir->remove_tree({safe => 0});
      }
      else {
         $log->info("skipping writing enviles");
         return;
      }
   } ## end if ($env_dir->exists &&...)
   $env_dir->mkpath;
   while (my ($name, $value) = each $spec->%*) {
      $env_dir->child($name)->spew_raw($value);
   }

   for my $zone ($self->zone_factory->items('dibspack_dirs')) {
      my $name = 'DIBS_DIR_' . uc $zone->name;
      $env_dir->child($name)->spew_raw($zone->container_base);
   }

   $env_dir->child('export-enviles.sh')->spew_raw(__export_enviles_sh());

   return $env_dir;
}

sub __export_enviles_sh {
   return <<'END';
#!/bin/sh

escape_var_value() {
   local value=$1
   printf '%s' "'"
   while : ; do
      case "$value" in
         (*\'*)
            printf '%s%s' "${value%%\'*}" "'\\''"
            value=${value#*\'}
            ;;
         (*)
            printf '%s' "$value"
            break
            ;;
      esac
   done
   printf '%s' "'"
}

export_all_enviles() {
   local base="${PWD%/}" file name value
   for file in "$base"/* ; do
      [ -e "$file" ]                       || continue
      [ "X${file#${file%???}}" != "X.sh" ] || continue
      name="$(basename "$file")"
      value="$(escape_var_value "$(cat "$file"; printf x)")"
      eval "export $name=${value%??}'"
   done
}

export_all_enviles

END
} ## end sub write_enviles

1;
__END__

package Dibs::Action::Instance;
use 5.024;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Path::Tiny qw< path >;
use List::Util qw< any >;
use Try::Catch;
use Module::Runtime qw< use_module >;
use experimental qw< postderef signatures >;
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
