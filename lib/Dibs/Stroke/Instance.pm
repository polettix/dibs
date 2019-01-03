package Dibs::Stroke::Instance;
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

sub container_path ($self, @args) {
   @args = $self->path if (!@args) && defined($self->path);
   return $self->_location->container_path(@args);
}

sub _location ($self) { # this is something executed inside the container!
   my @allowed_zones = $self->zone_factory->items('dibspacks_container');
   return $self->dibspack->location(@allowed_zones);
}

sub draw ($self, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   ARROW_OUTPUT('+', 'stroke ' . $self->name);

   my @carriers = ( # $self is considered implicitly
      ($args{env_carriers} // [])->@*,
      $self->dibspack, # this comes as last choice!
   );
   %args = (
      keep => 1, # keep by default, %args can override
      %args,
      env     => $self->merge_envs(@carriers),
      envile  => $self->merge_enviles(@carriers),
      indent  => $self->indent,
      workdir => $self->_workdir,
      command => $self->_command(\%args),
   );
   $args{user} = $self->user if defined $self->user;
   my ($exitcode, $cid, $out);

   my $enviles = $self->_write_enviles($args{envile});
   scope_guard { $enviles->remove_tree({safe => 0}) if $enviles };

   my @out = docker_run(%args);
   return @out;
}

sub _workdir ($self) { $self->zone_factory->item(ENVILE)->container_base }

sub _command ($self, $args) {
   my @args = map {
      my $ref = ref $_;
      if ($ref eq 'HASH') {
         my %data = $_->%*;
         my ($type, $data) =
           (scalar(keys %data) == 1)
           ? %data
           : (delete $data{type}, \%data);
         ouch 400, 'unknown type for arg of stroke' unless defined $type;
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
            ouch 400, "unrecognized arg for stroke (type: $type)";
         }
      } ## end if ($ref eq 'HASH')
      elsif (!$ref) {
         $_;
      }
      else {
         ouch 400, "invalid arg for stroke (ref: $ref)";
      }
   } $self->args->@*;
   return [$self->container_path, @args];
} ## end sub _command

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
