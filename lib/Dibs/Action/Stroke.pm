package Dibs::Action::Stroke; # Docker action over image
use 5.024;
use Log::Any '$log';
use Dibs::Config ':constants';
use Dibs::Docker qw< docker_commit docker_rm docker_run >;
use Ouch ':trytiny_var';
use Try::Catch;
use Guard;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';
with 'Dibs::Role::EnvCarrier';

has '+output_char' => (default => '-');
has args => (is => 'ro', default => sub { return [] });
has indent => (is => 'ro', default => 42); # FIXME understand/comment!
has pack => (is => 'ro', required => 1);
has path => (is => 'ro', required => 1); # path inside container
has user => (is => 'ro', default => undef);
has zone_factory => (is => 'ro', required => 1);

around create => sub ($orig, $class, %args) {
   my ($factory, $factory_args) = @args{qw< factory args >};
   my $dibspack_factory = $factory->dibspack_factory;

   my %spec =
      (ref($args{spec}) ? $args{spec} : $class->parse($args{spec}))->%*;

   my $pack_definition = $spec{pack} // $spec{dibspack};

   # strokes are saved where the container can reach 'em
   my $zf = $spec{zone_factory} = $args{factory}->zone_factory;
   my $zone = $zf->item(PROJECT);

   my $pk = $spec{pack} = $dibspack_factory->item(
      $pack_definition,
      dynamic_zone => $zone,
      $factory_args->%*,
   );
   $spec{path} = $pk->container_path($spec{path});

   return $class->$orig(%args, spec => \%spec);
};

sub changes_for_commit ($self) { return }

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
         elsif ($type eq 'sketch_id') { $args->{sketch}->id }
         elsif ($type eq 'sketch_name') { $args->{sketch}->name }
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
   return [$self->path, @args];
}

sub execute ($self, $args = undef) {
   $self->pack->materialize;
   my @carriers = ($args->{env_carriers} // [])->@*;
   my %run_args = (
      keep => 1, # FIXME understand/comment, cargo cult
      $args->%*,
      env => $self->merge_envs(@carriers),
      envile => $self->merge_enviles(@carriers),
      indent => $self->indent,
      work_dir => $self->zone_factory->item(ENVILE)->container_base,
      command => $self->_command($args),
      user => 'root', # default
   );
   $run_args{user} = $self->user if defined $self->user;

   my $enviles = $self->_write_enviles($run_args{envile});
   scope_guard { $enviles->remove_tree({safe => 0}) if $enviles };
   
   my $cid;
   try {
      my ($ecode, $out);
      ($ecode, $cid, $out) = docker_run(%run_args);
      ouch 500, "stroke failed (exit code $ecode)" if $ecode;

      docker_commit($cid, $args->{image}, $self->changes_for_commit);

      (my $__cid, $cid) = ($cid, undef);
      docker_rm($__cid);
      $args->{out} = $out;
   }
   catch {
      my $e = $_;
      $log->error("SOMETHING WENT WRONG!");
      docker_rm($cid) if defined $cid;
      die $e;
   };

   return $args;
}

sub parse ($self, $spec) { ...  }

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

   for my $zone ($self->zone_factory->items('volumes')) {
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
