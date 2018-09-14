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
use experimental qw< postderef signatures >;
use Moo;
use Guard;
no warnings qw< experimental::postderef experimental::signatures >;
{ our $VERSION = '0.001'; }

use Dibs::Config ':all';
use Dibs::PacksList;
use Dibs::Docker;
use Dibs::Output;
use Dibs::Get;

use Exporter qw< import >;
our @EXPORT_OK = qw< main >;
our @EXPORT = ();

has _config => (is => 'ro', required => 1);
has _project_dir => (is => 'lazy');
has _host_project_dir => (is => 'lazy');
has _dibspacks_for => (is => 'ro', default => sub { return {} });
has all_metadata => (is => 'ro', default => sub { return {} });

sub add_metadata ($self, %pairs) {
   my $md = $self->all_metadata;
   $md->%* = ($md->%*, %pairs);
   return $self;
}

sub metadata_for ($self, $key) { $self->all_metadata->{$key} // undef }

sub name ($self, $step) {
   defined(my $n = $self->dconfig($step, 'commit', 'name'))
      or return $self->config('name');
   return $n;
}

sub config ($self, @path) {
   my $c = $self->_config;
   $c = $c->{shift @path} while defined($c) && @path && defined($path[0]);
   return $c;
}

sub dconfig ($self, @path) { $self->config(definitions => @path) }

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

sub steps ($self) {
   my $s = $self->config('steps');
   ouch 400, 'no step defined for execution'
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

sub set_logger($self) {
   my $logger = $self->config('logger') // ['Stderr', log_level => 'info'];
   my @logger = ref($logger) ? $logger->@* : $logger;
   Log::Any::Adapter->set(@logger);
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

sub dibspacks_for ($self, $step) {
   my $dfor = $self->_dibspacks_for;
   $dfor->{$step} //= Dibs::PacksList->new($step, $self->config);
   return $dfor->{$step}->list;
}

sub iterate_dibspacks ($self, $step) {
   # continue only if it makes sense...
   ouch 400, "no definitions for $step"
      unless defined $self->dconfig($step);
   my @dibspacks = $self->dibspacks_for($step) or return;

   # these "$args" (anon hash) contain arguments that are reused across all
   # dibspacks in this specific step
   my $args = $self->prepare_args($step);
   try {
      DIBSPACK:
      for my $dp (@dibspacks) {
         my $name = $dp->name;
         ARROW_OUTPUT('+', "dibspack $name");

         $args->{$_} = $self->coalesce_envs($dp, $step, $args, $_)
            for qw< env envile >;

         if ($dp->needs_fetch) {
            ARROW_OUTPUT('-', 'fetch dibspack');
            $dp->fetch;
         }

         ARROW_OUTPUT('-', 'run');
         $self->call_dibspack($dp, $step, $args);
      }
   }
   catch {
      $self->cleanup_tags($step, $args->{image});
      die $_; # rethrow
   };
   return $args->{image};
}

sub call_dibspack ($self, $dp, $step, $args) {
   my $p = path($dp->container_path)->stringify;
   my $stepname = $self->dconfig($step, 'step') // $step;
   my ($exitcode, $cid, $out);
   try {
      my $enviles = $self->write_enviles($args->{envile});
      scope_guard { $enviles->remove_tree({safe => 0}) if $enviles };

      ($exitcode, $cid, $out) = Dibs::Docker::docker_run(
         $args->%*,
         $dp->docker_run_args,

         # overriding everything above
         keep    => 1,
         volumes => [ $self->list_volumes ],
         command => [ $p, $self->list_dirs,
            $self->expand_command_args($step, $dp->args)],
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
   my $env_dir = path($self->resolve_project_path(ENVIRON), 'iles');
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
   return $env_dir;
}

sub coalesce_envs ($self, $dp, $step, $args, $key = 'env') {
   my $stepc = $self->dconfig($step);
   return __merge_envs(
      $self->config(defaults => $key),
      $stepc->{$key},
      $dp->$key,
      $self->all_metadata,
      {
         DIBS_FROM_IMAGE => $stepc->{from},
         DIBS_WORK_IMAGE => $args->{image},
      },
   );
}

sub prepare_args ($self, $step) {
   my $stepc = $self->dconfig($step);
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
   my $cfg = $self->dconfig($step, 'commit');
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
            $self->dconfig($step, 'step') // $step;
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

sub run_step ($self, $name) {
   # normalize the configuration for "commit" in the step before going on,
   # it might be a full associative array or some DWIM stuff
   my $sc = $self->dconfig($name);
   my $pc = $sc->{commit} = $self->normalized_commit_config($sc->{commit});

   # "do the thing"
   my $image = $self->iterate_dibspacks($name);

   # check if commit is required, otherwise default to ditch this container
   if ($pc->{keep}) {
      ARROW_OUTPUT('+', 'saving working image, commit required');
      return $self->additional_tags($name, $image, $pc->{tags})
   }
   else {
      ARROW_OUTPUT('+', 'removing working image, no commit required');
      return $self->cleanup_tags($name, $image);
   }
}

sub run ($self) {
   $self->set_logger;
   $self->set_run_metadata;
   $self->dump_configuration;

   my @tags_lists;
   try {
      $self->ensure_host_directories;

      for my $step ($self->steps) {
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
      my $tmp = __PACKAGE__->new(_config => $cmdenv);
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
	return $package->new(_config => $overall);
}

sub main (@as) {
   my $retval = try {
      __PACKAGE__->create_from_cmdline(@as)->run;
   }
   catch {
      $log->fatal(bleep);
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
