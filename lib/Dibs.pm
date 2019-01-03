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
use Scalar::Util qw< refaddr blessed >;
use YAML::XS qw< LoadFile >;
use experimental qw< postderef signatures >;
use Moo;
use Guard;
use Data::Dumper;
local $Data::Dumper::Indent = 1;
no warnings qw< experimental::postderef experimental::signatures >;
{ our $VERSION = '0.001'; }

use Dibs::Config::Slice;
use Dibs::Cache;
use Dibs::Config ':all';
use Dibs::Inflater ':all';

#use Dibs::Process;
use Dibs::Action;
use Dibs::Pack;
use Dibs::Docker;
use Dibs::Output;
use Dibs::Get;
use Dibs::ZoneFactory;

has allow_dirty => (
   is       => 'ro',
   default  => 0,
   init_arg => 'dirty',
   coerce   => sub ($x) { $x ? 1 : 0 },
);

has project_dir => (
   is       => 'ro',
   required => 1,
   coerce   => sub ($path) { return path($path)->absolute },
);

has zone_factory => (
   is       => 'ro',
   required => 1,
   coerce   => sub ($def) {
      return $def if blessed($def) && $def->isa('Dibs::ZoneFactory');
      return Dibs::ZoneFactory->new($def);
   },
);

{    # generate members & methods:
       #
       # - action_cache    (member)
       # - action_config   (member)
       # - action          (method)
       #
       # - dibspack_cache  (member)
       # - dibspack_config (member)
       # - dibspack        (method)
       #
       # - process_cache   (member)
       # - process_config  (member)
       # - process         (method)

   for my $type (qw< action dibspack process >) {
      has "${type}_cache" => (is => 'lazy');
      has "${type}_config" => (
         is      => 'ro',
         default => sub { return {} },
         coerce  => sub ($config) {
            blessed($config)
              ? $config
              : Dibs::Config::Slice->new(type => $type, items => $config);
         },
      );
      my $instancer = sub ($self, $name) {
         my $cache_method = $self->can("${type}_cache");
         my $cache        = $self->$cache_method;
         my $retval       = $cache->item($name);
         $retval = $cache->item($name, $retval->())
           if ref($retval) eq 'CODE';    # fulfill promise to compute
         return $retval;
      };

      # this comes last to restrict rule relaxing
      no strict 'refs';
      *{__PACKAGE__ . '::' . $type} = $instancer;
   } ## end for my $type (qw< action dibspack process >)
}

sub _build_action_cache ($self) {
   my $cache = Dibs::Cache->new(type => 'action');
   my $cfg   = $self->action_config;
   my $dc    = $self->dibspack_cache;
   $cache->item($_, sub { __realize_action($cfg, $dc, $_) })
     for $cfg->names;
   return $cache;
} ## end sub _build_action_cache ($self)

sub _build_dibspack_cache ($self) {
   my $cache = Dibs::Cache->new(type => 'dibspack');
   my $cfg   = $self->dibspack_config;
   my $zf    = $self->zone_factory;
   $cache->item($_, sub { __realize_dibspack($cfg, $zf, $_) })
     for $cfg->names;
   return $cache;
} ## end sub _build_dibspack_cache ($self)

sub _build_process_cache ($self) {
   my $cache = Dibs::Cache->new(type => 'process');
   my $cfg   = $self->process_config;
   my $ac    = $self->action_cache;
   my $dc    = $self->dibspack_cache;
   my $zf    = $self->zone_factory;
   $cache->item($_, sub { __realize_process($cfg, $ac, $dc, $zf, $_) })
     for $cfg->names;
   return $cache;
} ## end sub _build_process_cache ($self)

# this can be moved inside its own factory class
sub __realize_action ($config, $dibspack_cache, $name) { ... }

sub __realize_dibspack ($config, $zone_factory, $x) {
   return Dibs::Pack::create_dibspack(
      $config->expanded_item($x),
      zone_factor => $zone_factory,
      dynamic_zone => HOST_DIBSPACKS, # default zone FIXME double check
      # cloner = sub { ... }, # FIXME add cloner maybe?
   );
}

sub __realize_process ($config, $zone_factory, $name) { ... }

__END__
has _steps => (
   is       => 'ro',
   default  => sub { return {} },
   init_arg => 'steps',
);

has workflow => (
   is       => 'ro',
   required => 1,
   isa      => sub ($v) {
      ouch 400, 'invalid workflow' unless ref($v) eq 'ARRAY' && $v->@*;
   },
);


has _dibspack_for => (is => 'ro', default => sub { return {} });
has all_metadata  => (is => 'ro', default => sub { return {} });

sub process ($self, $name) {
   my $pf = $self->_process_for;
   if (! exists $pf->{$name}) {
      my $rpf = $self->_raw_process_for;
      my $def = $rpf->{$name} or ouch 404, "missing process '$name'";
      expand_hash($def, $rpf); # manage extends...

      my @as = $self->build_actions_array($name, delete $def->{&ACTIONS});
      $pf->{$name} = Dibs::Process->new(
         $def->%*,
         actions => flatten_array(\@as, $self->_raw_actions),
      );
   }
   return $pf->{$name};
}

sub build_actions_array ($self, $name, $ds) {

   # first of all check what comes from the configuration
   return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) if defined $ds;

   # now check for a .dibsactions (&DPFILE) in the source directory
   my $src_dir = $self->zone(SRC)->host_base;
   my $das_path = $src_dir->child(DPFILE);

   # if a plain file, just take whatever is written inside
   if ($das_path->is_file) {
      $ds = LoadFile($das_path->stringify)->{$name};
      return (ref($ds) eq 'ARRAY' ? $ds->@* : $ds);
   }

   # if dir, iterate over its contents
   if ($ds_path->child($step)->is_dir) {
      return map {
         my $child = $_;
         my $bn    = $child->basename;
         next if ($bn eq '_') || (substr($bn, 0, 1) eq '.');
         $child->child(OPERATE) if $child->is_dir;
         next unless $child->is_file && -x $child;
         {
            type => SRC,
            path => $child->relative($src_dir),
         };
      } sort { $a cmp $b } $ds_path->child($step)->children;
   } ## end if ($ds_path->child($step...))

   ouch 400, "no actions found for step $step";
   return;    # unreached
} ## end sub build_actions_array

sub BUILDARGS ($self, @as) {
   my %args = (@as && ref($as[0])) ? $as[0]->%* : @as;

   ouch 400, 'missing project_dir' unless length($args{project_dir} // '');

   $args{zone_factory} //= Dibs::ZoneFactory->new(
      {
         project_dir    => $args{project_dir},
         zone_specs_for => $args{zone_specs_for},
      }
   ) if exists $args{zone_specs_for};
   ouch 400, 'missing zone_factory' unless defined($args{zone_factory});

   $args{cache} //= delete $args{config};

   return \%args;
} ## end sub BUILDARGS

sub zone ($self, $name) { $self->zone_factory->zone_for($name) }

sub dibspack_for ($self, $spec) {
   my $dibspack_for = $self->config(DIBSPACKS) // {};
   if (!ref($spec)) {
      my $ns = $dibspack_for->{$spec}
        or ouch 400, "no dibspack '$spec' in defaults, typo?";
      $spec = $ns;
   }
   __expand_extends($spec, DIBSPACK, $dibspack_for)
     if ref($spec) eq 'HASH';   # in-place expansion of hash specifications
   my $dibspack = Dibs::Pack->create($spec, $self);

   # materialize and cache dibspack if needed
   my $id = $dibspack->id;
   my $df = $self->_dibspack_for;
   if (!exists($df->{$id})) {
      if ($dibspack->can('materialize')) {
         ARROW_OUTPUT('-', 'materialize dibspack');
         $dibspack->materialize;
      }
      $df->{$id} = $dibspack;
   } ## end if (!exists($df->{$id}...))

   return $df->{$id};
} ## end sub dibspack_for

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
   return (@subdirs ? $pd->child(@subdirs) : $pd);
}

sub host_project_dir ($self, @subdirs) {
   my $hpd = $self->_host_project_dir;
   return (@subdirs ? $hpd->child(@subdirs) : $hpd);
}

sub _resolve_path ($self, $space, $zone, $path) {
   defined(my $base = $self->config($space => $zone))
     or ouch 400, "unknown zone $zone for resolution inside container";
   my $retval = path($base);
   $retval = $retval->child($path) if length($path // '');
   return $retval->stringify;
} ## end sub _resolve_path

sub resolve_project_path ($self, $zone, $path = undef) {
   $self->project_dir($self->_resolve_path(project_dirs => $zone, $path));
}

sub resolve_container_path ($self, $zone, $path = undef) {
   return $self->_resolve_path(container_dirs => $zone, $path);
}

sub set_run_metadata ($self) {
   $self->add_metadata(DIBS_ID => strftime("%Y%m%d-%H%M%S-$$", gmtime));
}

sub dump_configuration ($self) {
   require Data::Dumper;
   local $Data::Dumper::Indent = 1;
   $log->debug(Data::Dumper::Dumper($self->config));
   return;
} ## end sub dump_configuration ($self)

sub origin_onto_src ($self, $origin) {
   my $src_dir = $self->zone(SRC)->host_base;
   my $dirty   = $self->allow_dirty // undef;
   Dibs::Get::get_origin($origin, $src_dir,
      {clean_only => !$dirty, wipe => 1});
   return $src_dir;
} ## end sub origin_onto_src

sub ensure_host_directories ($self) {
   my $is_local = $self->config('local');

   my $pd   = $self->project_dir;
   my $pds  = $self->config('project_dirs');
   my @dirs = (CACHE, DIBSPACKS, ENVIRON);

   # in local-mode the current (development) directory is used directly
   # as src, which might make it inconvenient because the project dir
   # would become "visibile" inside it. EMPTY will shadow it.
   push @dirs, EMPTY if $is_local;

   # SRC might be special and require to be fetched from somewhere
   my $origin = $self->config('origin');
   if (defined $origin) {
      if (!$self->config('has_cloned')) {
         ARROW_OUTPUT('=', "clone of origin '$origin'");
         $self->origin_onto_src($origin);
      }
   } ## end if (defined $origin)
   elsif (!$is_local) { push @dirs, SRC }

   # create missing directories in host
   for my $name (@dirs) {
      my $subdir = $pds->{$name};
      $pd->child($subdir)->mkpath;
   }

   return;
} ## end sub ensure_host_directories ($self)

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
      } ## end DIBSPACK: for my $action (@actions)
   } ## end try
   catch {
      $self->cleanup_tags($step, $args->{image});
      die $_;    # rethrow
   };
   return $args->{image};
} ## end sub iterate_actions

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
         volumes => [$self->list_volumes],
         workdir => $self->resolve_container_path(ENVILE),
         command => [$p, $self->expand_command_args($step, $action->args)]
      );
      ouch 500, "failure ($exitcode)" if $exitcode;

      Dibs::Docker::docker_commit($cid, $args->@{qw< image changes >});
      (my $__cid, $cid) = ($cid, undef);
      Dibs::Docker::docker_rm($__cid);
   } ## end try
   catch {
      Dibs::Docker::docker_rm($cid) if defined $cid;
      die $_;    # rethrow
   };
   return;
} ## end sub call_action

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
   } ## end if ($env_dir->exists &&...)
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

   return $env_dir;
} ## end sub write_enviles

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
} ## end sub metadata_for_envile

sub coalesce_envs ($self, $action, $step, $args, $key = 'env') {
   my $stepc  = $self->sconfig($step);
   my $method = $self->can("metadata_for_$key");
   return __merge_envs(
      $self->config(defaults => $key),
      $stepc->{$key}, $action->$key,
      ($method ? $self->$method($action, $step, $args) : ()),
   );
} ## end sub coalesce_envs

sub prepare_args ($self, $step) {
   my $stepc = $self->sconfig($step);
   my $from  = $stepc->{from};
   my $to    = $self->target_name($step);
   my $image = try {
      Dibs::Docker::docker_tag($from, $to);
   }
   catch {
      ouch 400,
        "Unable to use image '$from' as '$to'. Maybe it can be build with "
        . "some other different step before?";
   };
   return {
      image       => $image,
      changes     => $self->changes_for_commit($step),
      project_dir => $self->project_dir,
   };
} ## end sub prepare_args

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
} ## end sub normalized_commit_config

sub changes_for_commit ($self, $step) {
   my $cfg = $self->sconfig($step, 'commit');
   my %changes = (
      cmd        => [],
      entrypoint => [qw< /bin/sh -l >],
   );
   for my $key (qw< entrypoint cmd workdir user >) {
      $changes{$key} = $cfg->{$key} if defined $cfg->{$key};
   }
   return \%changes;
} ## end sub changes_for_commit

sub cleanup_tags ($self, $step, @tags) {
   for my $tag (@tags) {
      try { Dibs::Docker::docker_rmi($tag) }
      catch { $log->error("failed to remove $tag") };
   }
   return;
} ## end sub cleanup_tags

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
         } ## end else [ if (($tag eq '*') || (...))]
      } ## end for my $tag ($new_tags->...)
   } ## end try
   catch {
      $self->cleanup_tags($step, @tags);
      die $_;    # rethrow
   };

   # get rid of the default image, if "makes sense". Never get rid of
   # a tag if it's the only one, or requested to keep it.
   $self->cleanup_tags($step, shift @tags)
     unless (@tags == 1) || $keep_default;

   return @tags;
} ## end sub additional_tags

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
   } ## end while (@envs)
   return \%all;
} ## end sub __merge_envs (@envs)

sub list_dirs ($self) {
   my $cds = $self->config('container_dirs');
   my $dds = $self->config('dibspack_dirs');
   map { $cds->{$_} } $dds->@*;
}

sub list_volumes ($self) {
   my $pd  = $self->host_project_dir;
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
            my $subdir            = $host_prj_dir->relative($host_src_dir);
            my $container_src_dir = path($cds->{&SRC})->absolute;
            my $target = $subdir->absolute($container_src_dir)->stringify;
            @r = ($pd->child($pds->{$name})->stringify, $target, @mode);
         } ## end if ($host_src_dir->subsumes...)
      } ## end elsif ($is_local && ($name...))

      # otherwise everything is looked for inside the project_dir and
      # EMPTY is ignored
      elsif ($name ne EMPTY) {
         @r = ($pd->child($pds->{$name})->stringify, $cds->{$name}, @mode);
      }

      # save a reference if there's something to be saved, skip otherwise
      @r ? \@r : ();
   } $self->config('volumes')->@*;
} ## end sub list_volumes ($self)

sub expand_command_args ($self, $step, @args) {
   map {
      my $ref = ref $_;
      if ($ref eq 'HASH') {
         my %data = $_->%*;
         my ($type, $data) =
           (scalar(keys %data) == 1)
           ? %data
           : (delete $data{type}, \%data);
         ouch 'unknown type for arg of dibspack' unless defined $type;
         ($type, $data) = ($data, undef) if $type eq 'type';
         if (my ($ptype) = $type =~ m{\A path_ (.+) \z}mxs) {
            $type = 'path';
            $data = {$ptype => $data};
         }
         if ($type eq 'path') {
            ouch 400, 'unrecognized request for path resolution'
              unless (ref($data) eq 'HASH')
              && (scalar(keys $data->%*) == 1);
            $self->resolve_container_path($data->%*);
         } ## end if ($type eq 'path')
         elsif ($type eq 'step_id') { $step }
         elsif ($type eq 'step_name') {
            $self->sconfig($step, 'step') // $step;
         }
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
   } @args;
} ## end sub expand_command_args

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
} ## end sub step_config_for

sub run_step ($self, $step) {
   my $sc = $self->step_config_for($step);
   $log->debug(Dumper $sc);
   my $pc = $sc->{commit};

   # "do the thing"
   my $image = $self->iterate_actions($step);

   # check if commit is required, otherwise default to ditch this container
   if ($pc->{keep}) {
      ARROW_OUTPUT('+', 'saving working image, commit required');
      return $self->additional_tags($step, $image, $pc->{tags});
   }
   else {
      ARROW_OUTPUT('+', 'removing working image, no commit required');
      return $self->cleanup_tags($step, $image);
   }
} ## end sub run_step

sub run ($self) {
   $self->set_run_metadata;
   $self->dump_configuration;

   my @tags_lists;
   try {
      $self->ensure_host_directories;

      for my $step ($self->workflow->@*) {
         ARROW_OUTPUT('=', "step $step");
         if (my @tags = $self->run_step($step)) {
            push @tags_lists, [$step, @tags];
         }
      } ## end for my $step ($self->workflow...)
      for (@tags_lists) {
         my ($step, @tags) = $_->@*;
         say "$step: @tags";
      }
   } ## end try
   catch {
      my $e = $_;
      $self->cleanup_tags($_->@*) for reverse @tags_lists;
      die $e;
   };
   return 0;
} ## end sub run ($self)

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
