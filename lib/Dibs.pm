package Dibs;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Path::Tiny qw< path cwd >;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use POSIX qw< strftime >;
use Scalar::Util qw< refaddr >;
use YAML::XS qw< LoadFile >;
use experimental qw< postderef signatures >;
use Moo;
use Guard;
use Data::Dumper; local $Data::Dumper::Indent = 1;
no warnings qw< experimental::postderef experimental::signatures >;
{ our $VERSION = '0.001'; }

use Dibs::Config ':all';
use Dibs::Action;
use Dibs::Pack;
use Dibs::Docker;
use Dibs::Output;
use Dibs::Get;

has _config => (
   is => 'ro',
   required => 1,
   init_arg => 'config',
);
has _project_dir => (is => 'lazy');
has _host_project_dir => (is => 'lazy');
has _actions_for => (is => 'ro', default => sub { return {} });
has _dibspack_for => (is => 'ro', default => sub { return {} });
has all_metadata => (is => 'ro', default => sub { return {} });

sub __expand_extends ($hash, $type, $definition_for, $flags = {}) {
   defined(my $ds = delete($hash->{extends})) or return;
   $definition_for //= {};
   for my $source (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) {
      my $defaults = (ref($source) ? $source : $definition_for->{$source})
         or ouch 500, "no $type '$source', typo?";

      # protect aginst circular dependencies
      my $id  = refaddr($defaults);
      if ($flags->{$id}++) {
         my $name = ref($source) ? 'internal reference' : $source;
         ouch 400, "circular reference involving $type ($name)";
      }

      # $defaults will hold the defaults to be merged into $hash. Make
      # sure to recursively resolve its defaults though
      __expand_extends($defaults, $type, $definition_for, $flags);

      # merge hashes and proceed to next default
      $hash->%* = ($defaults->%*, $hash->%*);

      # the same default might be ancestor to multiple things
      delete $flags->{$id};
   }
   return $hash;
}

sub __set_logger (@args) {
   state $set = 0;
   return if $set++;
   my @logger = scalar(@args) ? @args : ('Stderr', log_level => 'info');
   Log::Any::Adapter->set(@logger);
}

sub build_actions_array ($self, $step) {
   # first of all check what comes from the configuration
   my $ds = $self->sconfig($step => ACTIONS);
   return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibsactions in the source directory
   my $src_dir = $self->resolve_project_path(SRC);
   my $ds_path = $src_dir->child(DPFILE);

   # if a plain file, just take whatever is written inside
   if ($ds_path->is_file) {
      $ds = LoadFile($ds_path->stringify)->{$step};
      return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds);
   }

   # if dir, iterate over its contents
   if ($ds_path->child($step)->is_dir) {
      return  map {
         my $child = $_;
         my $bn = $child->basename;
         next if ($bn eq '_') || (substr($bn, 0, 1) eq '.');
         $child->child(OPERATE) if $child->is_dir;
         next unless $child->is_file && -x $child;
         {
            type => SRC,
            path => $child->relative($src_dir),
         };
      } sort { $a cmp $b } $ds_path->child($step)->children;
   }

   ouch 400, "no actions found for step $step";
   return; # unreached
}

sub dibspack_for ($self, $spec) {
   my $dibspack_for = $self->config(DIBSPACKS) // {};
   if (! ref($spec)) {
      my $ns = $dibspack_for->{$spec}
         or ouch 400, "no dibspack '$spec' in defaults, typo?";
      $spec = $ns;
   }
   __expand_extends($spec, DIBSPACK, $dibspack_for)
      if ref($spec) eq 'HASH'; # in-place expansion of hash specifications
   my $dibspack = Dibs::Pack->create($spec, $self);

   # materialize and cache dibspack if needed
   my $id = $dibspack->id;
   my $df = $self->_dibspack_for;
   if (! exists($df->{$id})) {
      if ($dibspack->can('materialize')) {
         ARROW_OUTPUT('-', 'materialize dibspack');
         $dibspack->materialize;
      }
      $df->{$id} = $dibspack;
   }

   return $df->{$id};
}

sub add_metadata ($self, %pairs) {
   my $md = $self->all_metadata;
   $md->%* = ($md->%*, %pairs);
   return $self;
}

sub metadata_for ($self, $key) { $self->all_metadata->{$key} // undef }

sub name ($self, $step) {
   defined(my $n = $self->sconfig($step, 'commit', 'name'))
      or return $self->config('name');
   return $n;
}

sub config ($self, @path) {
   my $c = $self->_config;
   $c = $c->{shift @path} while defined($c) && @path && defined($path[0]);
   return $c;
}

sub sconfig ($self, @path) { $self->config(STEPS, @path) }

sub _build__project_dir ($self) {
   return path($self->config('project_dir'))->absolute;
}

sub _build__host_project_dir ($self) {
   return path($self->config('host_project_dir') // $self->project_dir);
}

sub project_dir ($self, @subdirs) {
   my $pd = $self->_project_dir;
   return(@subdirs ? $pd->child(@subdirs) : $pd);
}

sub host_project_dir ($self, @subdirs) {
   my $hpd = $self->_host_project_dir;
   return(@subdirs ? $hpd->child(@subdirs) : $hpd);
}

sub workflow ($self) {
   my $s = $self->config(WORKFLOW);
   ouch 400, 'no workflow defined for execution'
      unless (ref($s) eq 'ARRAY') && scalar($s->@*);
   return $s->@*;
}

sub _resolve_path ($self, $space, $zone, $path) {
   defined (my $base = $self->config($space => $zone))
      or ouch 400, "unknown zone $zone for resolution inside container";
   my $retval = path($base);
   $retval = $retval->child($path) if length($path // '');
   return $retval->stringify;
}

sub resolve_project_path ($self, $zone, $path = undef) {
   $self->project_dir($self->_resolve_path(project_dirs => $zone, $path));
}

sub resolve_container_path ($self, $zone, $path = undef) {
   return $self->_resolve_path(container_dirs => $zone, $path);
}

sub set_logger($self = undef) {
   my $logger = $self->config('logger') // [];
   __set_logger($logger->@*);
}

sub set_run_metadata ($self) {
   $self->add_metadata(DIBS_ID => strftime("%Y%m%d-%H%M%S-$$", gmtime));
}

sub dump_configuration ($self) {
   require Data::Dumper;
   local $Data::Dumper::Indent = 1;
   $log->debug(Data::Dumper::Dumper($self->config));
   return;
}

sub wipe_directory ($self, $name) {
   my $dir_for = $self->config('project_dirs');
   my $dir = $self->project_dir($dir_for->{$name});
   if ($dir->exists) {
      try   { $dir->remove_tree({safe => 0}) }
      catch { ouch 500, "cannot delete $dir, check permissions maybe?" };
   }
   return $dir;
}

sub origin_onto_src ($self, $origin) {
   my $src_dir = $self->wipe_directory(SRC);
   my $dirty = $self->config('dirty') // undef;
   Dibs::Get::get_origin($origin, $src_dir, {clean_only => !$dirty});
   return path($src_dir);
}

sub ensure_host_directories ($self) {
   my $is_local = $self->config('local');

   my $pd = $self->project_dir;
   my $pds = $self->config('project_dirs');
   my @dirs = (CACHE, DIBSPACKS, ENVIRON);

   # in local-mode the current (development) directory is used directly
   # as src, which might make it inconvenient because the project dir
   # would become "visibile" inside it. EMPTY will shadow it.
   push @dirs, EMPTY if $is_local;

   # SRC might be special and require to be fetched from somewhere
   my $origin = $self->config('origin');
   if (defined $origin) {
      if (! $self->config('has_cloned')) {
         ARROW_OUTPUT('=', "clone of origin '$origin'");
         $self->origin_onto_src($origin);
      }
   }
   elsif (!$is_local)   { push @dirs, SRC }

   # create missing directories in host
   for my $name (@dirs) {
      my $subdir = $pds->{$name};
      $pd->child($subdir)->mkpath;
   }

   return;
}

sub actions_for ($self, $step) {
   my $afor = $self->_actions_for;
   if (! $afor->{$step}) {
      # build the flattened list of actions for this step. We have to
      # simulate a stack of recursive calls so that we can allow nested
      # definitions; on the way we will check for circular inclusions
      # and complain about them
      my $adf = $self->config(ACTIONS) // {};
      my @stack = { queue => [$self->build_actions_array($step)] };
      $afor->{$step} = \my @retval;
      my %seen; # circular inclusion avoidance
      ITEM:
      while (@stack) {
         my $queue = $stack[-1]{queue};
         if (scalar($queue->@*) == 0) {
            my $exhausted_frame = pop @stack;

            # the "parent" of this frame can be removed from circular
            # inclusion avoidance from now on
            delete $seen{$exhausted_frame->{parent}}
               if exists $exhausted_frame->{parent};

            next ITEM;
         }

         my $item = shift $queue->@*;
         my $ref = ref $item;
         if ($ref eq 'ARRAY') { # array -> do "recursive" flattening
            my $id = refaddr($item);
            ouch 400, "circular reference in actions for $step"
               if $seen{$id}++;

            # this $id will trigger circular inclusion error from now
            # until the stack frame is eventually removed
            push @stack, { parent => $id, queue  => [$item->@*] };

            next ITEM;
         }
         elsif ($ref eq 'HASH') {
            __expand_extends($item, ACTIONS, $adf);
            push @retval, Dibs::Action->create($item, $self);
            next ITEM;
         }
         elsif ((! $ref) && exists($adf->{$item})) {
            unshift $queue->@*, $adf->{$item};
            next ITEM;
         }
         elsif (! $ref) {
            push @retval, Dibs::Action->create($item, $self);
            next ITEM;
         }
         else {
            ouch 400, "unknown action of type $ref";
         }
      }
   }
   return $afor->{$step}->@*;
}

sub iterate_actions ($self, $step) {
   # continue only if it makes sense...
   my @actions = $self->actions_for($step) or return;

   # these "$args" (anon hash) contain arguments that are reused across all
   # actions in this specific step
   my $args = $self->prepare_args($step);
   try {
      DIBSPACK:
      for my $action (@actions) {
         my $name = $action->name;
         ARROW_OUTPUT('+', "action $name");

         $args->{$_} = $self->coalesce_envs($action, $step, $args, $_)
            for qw< env envile >;

         ARROW_OUTPUT('-', 'run');
         $self->call_action($action, $step, $args);
      }
   }
   catch {
      $self->cleanup_tags($step, $args->{image});
      die $_; # rethrow
   };
   return $args->{image};
}

sub call_action ($self, $action, $step, $args) {
   my $p = path($action->container_path)->stringify;
   my $stepname = $self->sconfig($step, 'step') // $step;
   my ($exitcode, $cid, $out);
   try {
      my $enviles = $self->write_enviles($args->{envile});
      scope_guard { $enviles->remove_tree({safe => 0}) if $enviles };

      ($exitcode, $cid, $out) = Dibs::Docker::docker_run(
         $args->%*,
         $action->docker_run_args,

         # overriding everything above
         keep    => 1,
         volumes => [ $self->list_volumes ],
         workdir => $self->resolve_container_path(ENVILE),
         command => [ $p, $self->expand_command_args($step, $action->args)]
      );
      ouch 500, "failure ($exitcode)" if $exitcode;

      Dibs::Docker::docker_commit($cid, $args->@{qw< image changes >});
      (my $__cid, $cid) = ($cid, undef);
      Dibs::Docker::docker_rm($__cid);
   }
   catch {
      Dibs::Docker::docker_rm($cid) if defined $cid;
      die $_; # rethrow
   };
   return;
}

sub write_enviles ($self, $spec) {
   my $env_dir = path($self->resolve_project_path(ENVILE));
   if ($env_dir->exists && !$env_dir->is_dir) {
      if ($env_dir->is_dir) {
         $env_dir->remove_tree({safe => 0});
      }
      else {
         $log->info("skipping writing enviles");
         return;
      }
   }
   $env_dir->mkpath;
   while (my ($name, $value) = each $spec->%*) {
      $env_dir->child($name)->spew_raw($value);
   }

   my $cds = $self->config('container_dirs');
   for my $dir_name ($self->config('dibspack_dirs')->@*) {
      my $name = 'DIBS_DIR_' . uc($dir_name);
      $env_dir->child($name)->spew_raw($cds->{$dir_name});
   }

   $env_dir->child('export-enviles.sh')->spew_raw(<<'END');
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

export_envile() {
   local name="$(basename "$1")"
   local value="$(escape_var_value "$(cat "$1"; printf x)")"
   eval "export $name=${value%??}'"
}

export_enviles_from() {
   local base="${1%/}" f file
   shift
   for f in "$@" ; do
      file="$base/$f"
      [ -e "$file" ] && export_envile "$file"
   done
}

export_all_enviles_from() {
   local base="${1%/}" file
   for file in "$base"/DIBS* ; do
      [ -e "$file" ] && export_envile "$file"
   done
}

if [ "$#" -gt 0 ] ; then
   export_enviles_from "$PWD" "$@"
else
   export_all_enviles_from "$PWD"
fi

END

   return $env_dir;
}

sub metadata_for_envile ($self, $action, $step, $args) {
   my $step_name = $self->sconfig($step, 'step') // $step;
   return (
      $self->all_metadata,
      {
         DIBS_FROM_IMAGE => ($self->sconfig($step, 'from') // ''),
         DIBS_WORK_IMAGE => $args->{image},
         DIBS_STEP       => $step_name,
      },
   );
}

sub coalesce_envs ($self, $action, $step, $args, $key = 'env') {
   my $stepc = $self->sconfig($step);
   my $method = $self->can("metadata_for_$key");
   return __merge_envs(
      $self->config(defaults => $key),
      $stepc->{$key},
      $action->$key,
      ($method ? $self->$method($action, $step, $args) : ()),
   );
}

sub prepare_args ($self, $step) {
   my $stepc = $self->sconfig($step);
   my $from = $stepc->{from};
   my $to   = $self->target_name($step);
   my $image = try {
      Dibs::Docker::docker_tag($from, $to);
   }
   catch {
      ouch 400,
         "Unable to use image '$from' as '$to'. Maybe it can be build with "
       . "some other different step before?";
   };
   return {
      image => $image,
      changes => $self->changes_for_commit($step),
      project_dir => $self->project_dir,
   };
}

sub normalized_commit_config ($self, $cfg) {
   return {keep => 0} unless $cfg;

   my $ref = ref $cfg;
   return {keep => 1, $cfg->%*} if $ref eq 'HASH';
   return {keep => 1, tags => $cfg} if $ref eq 'ARRAY';

   # the "false" one is probably overkill here
   return {keep => 0}
      if $cfg =~ m{\A(?:n|N|no|No|NO|false|False|FALSE|off|Off|OFF)\z}mxs;
   return {keep => 1, tags => [':default:']}
      if $cfg =~ m{\A(?:y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON)\z}mxs;

   ouch 400, "unhandled ref type $ref for commit field" if $ref;
   return {keep => 1, tags => [$cfg]};
}

sub changes_for_commit ($self, $step) {
   my $cfg = $self->sconfig($step, 'commit');
   my %changes = (
      cmd => [],
      entrypoint => [qw< /bin/sh -l >],
   );
   for my $key (qw< entrypoint cmd workdir user >) {
      $changes{$key} = $cfg->{$key} if defined $cfg->{$key};
   }
   return \%changes;
}

sub cleanup_tags ($self, $step, @tags) {
   for my $tag (@tags) {
      try { Dibs::Docker::docker_rmi($tag) }
      catch { $log->error("failed to remove $tag") };
   }
   return;
}

sub additional_tags ($self, $step, $image, $new_tags) {
   return ($image) unless $new_tags;

   my @tags = $image;
   my $keep_default;
   try {
      my $name = $self->name($step);
      for my $tag ($new_tags->@*) {
         if (($tag eq '*') || ($tag eq ':default:')) {
            $keep_default = 1;
         }
         else {
            my $dst = $tag =~ m{:}mxs ? $tag : "$name:$tag";
            next if $dst eq $image;
            Dibs::Docker::docker_tag($image, $dst);
            push @tags, $dst;
         }
      }
   }
   catch {
      $self->cleanup_tags($step, @tags);
      die $_; # rethrow
   };

   # get rid of the default image, if "makes sense". Never get rid of
   # a tag if it's the only one, or requested to keep it.
   $self->cleanup_tags($step, shift @tags)
      unless (@tags == 1) || $keep_default;

   return @tags;
}

sub __merge_envs (@envs) {
   my %all;
   while (@envs) {
      my $env = shift @envs;
      if (ref($env) eq 'ARRAY') {
         unshift @envs, $env->@*;
      }
      elsif (ref($env) eq 'HASH') {
         %all = (%all, $env->%*);
      }
      elsif (ref $env) {
         ouch 400, "unsupported env of ref $env";
      }
      elsif (defined $env) {
         $all{$env} = $ENV{$env} if exists $ENV{$env};
      }
   }
   return \%all;
}

sub list_dirs ($self) {
   my $cds = $self->config('container_dirs');
   my $dds = $self->config('dibspack_dirs');
   map { $cds->{$_} } $dds->@*;
}

sub list_volumes ($self) {
   my $pd = $self->host_project_dir;
   my $pds = $self->config('project_dirs');
   my $cds = $self->config('container_dirs');

   my $is_local = $self->config('local');
   return map {
      my ($name, @mode) = ref($_) ? $_->@* : $_;
      my @r;

      # local mode has a special treatment of SRC (mounts cwd directly)
      # and adopts EMPTY to shadow the project_dir if it's inside SRC
      if ($is_local && ($name eq SRC)) {
         @r = (cwd->stringify, $cds->{$name}, @mode);
      }
      elsif ($is_local && ($name eq EMPTY)) {
         my $host_src_dir = cwd;
         my $host_prj_dir = $pd->absolute;
         if ($host_src_dir->subsumes($host_prj_dir)) {
            my $subdir = $host_prj_dir->relative($host_src_dir);
            my $container_src_dir = path($cds->{&SRC})->absolute;
            my $target = $subdir->absolute($container_src_dir)->stringify;
            @r = ($pd->child($pds->{$name})->stringify, $target, @mode);
         }
      }
      # otherwise everything is looked for inside the project_dir and
      # EMPTY is ignored
      elsif ($name ne EMPTY) {
         @r = ($pd->child($pds->{$name})->stringify, $cds->{$name}, @mode);
      }

      # save a reference if there's something to be saved, skip otherwise
      @r ? \@r : ();
   } $self->config('volumes')->@*;
}

sub expand_command_args ($self, $step, @args) {
   map {
      my $ref = ref $_;
      if ($ref eq 'HASH') {
         my %data = $_->%*;
         my ($type, $data) = (scalar(keys %data) == 1) ? %data
            : (delete $data{type}, \%data);
         ouch 'unknown type for arg of dibspack' unless defined $type;
         ($type, $data) = ($data, undef) if $type eq 'type';
         if (my ($ptype) = $type =~ m{\A path_ (.+) \z}mxs) {
            $type = 'path';
            $data = { $ptype => $data };
         }
         if ($type eq 'path') {
            ouch 400, 'unrecognized request for path resolution'
               unless (ref($data) eq 'HASH')
                   && (scalar(keys $data->%*) == 1);
            $self->resolve_container_path($data->%*);
         }
         elsif ($type eq 'step_id') { $step }
         elsif ($type eq 'step_name') {
            $self->sconfig($step, 'step') // $step;
         }
         else {
            ouch 400, "unrecognized arg for dibspack (type: $type)";
         }
      }
      elsif (!$ref) {
         $_;
      }
      else {
         ouch 400, "invalid arg for dibspack (ref: $ref)";
      }
   } @args;
}

sub target_name ($self, $step) {
   join ':', $self->name($step), $self->metadata_for('DIBS_ID');
}

sub step_config_for ($self, $name) {
   my $definitions_for = $self->sconfig;
   defined(my $sc = $definitions_for->{$name})
      or ouch 400, "no definitions for $name";

   # allow for recursive defaulting
   __expand_extends($sc, STEPS, $definitions_for);

   # normalize the configuration for "commit" in the step before going on,
   # it might be a full associative array or some DWIM stuff
   my $pc = $sc->{commit} = $self->normalized_commit_config($sc->{commit});

   return $sc;
}

sub run_step ($self, $step) {
   my $sc = $self->step_config_for($step);
   $log->debug(Dumper $sc);
   my $pc = $sc->{commit};

   # "do the thing"
   my $image = $self->iterate_actions($step);

   # check if commit is required, otherwise default to ditch this container
   if ($pc->{keep}) {
      ARROW_OUTPUT('+', 'saving working image, commit required');
      return $self->additional_tags($step, $image, $pc->{tags})
   }
   else {
      ARROW_OUTPUT('+', 'removing working image, no commit required');
      return $self->cleanup_tags($step, $image);
   }
}

sub run ($self) {
   $self->set_logger;
   $self->set_run_metadata;
   $self->dump_configuration;

   my @tags_lists;
   try {
      $self->ensure_host_directories;

      for my $step ($self->workflow) {
         ARROW_OUTPUT('=', "step $step");
         if (my @tags = $self->run_step($step)) {
            push @tags_lists, [$step, @tags];
         }
      }
      for (@tags_lists) {
         my ($step, @tags) = $_->@*;
         say "$step: @tags";
      }
   }
   catch {
      my $e = $_;
      $self->cleanup_tags($_->@*) for reverse @tags_lists;
      die $e;
   };
   return 0;
}

sub create_from_cmdline ($package, @as) {
   my $cmdenv = get_config_cmdenv(\@as);

   # start looking for the configuration file, refer it to the project dir
   # if relative, otherwise leave it as is
   my $cnfp = path($cmdenv->{config_file});

   # development mode is a bit special in that dibs.yml might be *inside*
   # the repository itself and the origin needs to be cloned beforehand
   my $is_alien = $cmdenv->{alien};
   my $is_development = $cmdenv->{development};
   if ((! $cnfp->exists) && ($is_alien || $is_development)) {
      my $tmp = $package->new(config => $cmdenv);
      $tmp->set_logger; # ensure we can output stuff on log channel

      my $origin = $cmdenv->{origin} // '';
      $origin = cwd() . $origin
         if ($origin eq '') || ($origin =~ m{\A\#.+}mxs);
      ARROW_OUTPUT('=', "early clone of origin '$origin'");

      my $src_dir = $tmp->origin_onto_src($origin);
      $cmdenv->{has_cloned} = 1;

      # there's no last chance, so config_file is set 
      $cnfp = $src_dir->child($cmdenv->{config_file});
   }

   ouch 400, 'no configuration file found' unless $cnfp->exists;

   my $overall = add_config_file($cmdenv, $cnfp);
	return $package->new(config => $overall);
}

sub main ($pkg, @as) {
   my $retval = try {
      my $dibs = $pkg->create_from_cmdline(@as);
      $dibs->run;
   }
   catch {
      __set_logger();
      $log->fatal(bleep);
      1;
   };
   return($retval // 0);
}

1;
__END__

=encoding utf8

=head1 NAME

dibs - Docker Image Build System

=head1 VERSION

Ask the version number to the script itself, calling:

   shell$ dibs --version


=head1 USAGE

   dibs [--usage] [--help] [--man] [--version]

   dibs [--project-dir|--project_dir|-p directory]
       command args...

=head1 EXAMPLES

   # fetch source into "src" subdirectory
   shell$ dibs fetch-src



=head1 DESCRIPTION

Handle different phases of building software and pack it as a trimmed Docker
image.

=head2 Project Directory

All operations are supposed to be performed within the context of a base
directory for the whole project. This directory can be set via option
L</--project_dir>. By default it is the current directory.

The project directory MUST contain a configuration file for the project,
called C<dibs.yml>.

=head1 OPTIONS

C<dibs> supports some command line options. Some of them are I<meta>, in
the sense that their goal is to provide information about C<dibs> itself;
other options are actually used by C<dibs> to do its intended job.

=head2 Meta-Options

The following I<meta-options> allow getting more info about C<dibs>
itself:

=over

=item --help

print a somewhat more verbose help, showing usage, this description of
the options and some examples from the synopsis.

=item --man

print out the full documentation for the script.

=item --usage

print a concise usage line and exit.

=item --version

print the version of the script.

=back


=head1 Real Options

The following options are supported by C<dibs> as part of its mission:

=over

=item project_dir

=item --project-dir

=item -p

   $ dibs --project-dir directory

set the base directory of the project. All files and directories are referred
to that directory. Defaults to the current directory.

=back

=head1 DIAGNOSTICS

Whatever fails will complain quite loudly.

=head1 CONFIGURATION AND ENVIRONMENT

C<dibs> can be configured in multiple ways. The following is a list of
where configurations are taken, in order of precedence (alternatives
higher in the list take precedence over those below them):

=over

=item *

command line options;

=item *

environment variables, in the form C<DIBS_XXXX> where C<XXXX> corresponds
to the command line option name (only for L</Real Options>, first
alternative for each of them), with initial hypens removed, intermediate
hyphens turned into underscores and all letters turned uppercase. For
example, option L</--project_dir> corresponds to environment variable
C<DPI_PROJECT_DIR>;

=item *

configuration file C<dibs.yml> as mandatorily found in the L</Project
Directory>.

=back


=head1 DEPENDENCIES

See C<cpanfile>.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests through the repository.


=head1 AUTHOR

Flavio Poletti C<polettix@cpan.org>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2016, Flavio Poletti C<polettix@cpan.org>.

This module is free software.  You can redistribute it and/or
modify it under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful,
but without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut
