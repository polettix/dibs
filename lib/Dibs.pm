package Dibs;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use YAML::Tiny qw< LoadFile >;
use Path::Tiny qw< path cwd >;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use POSIX qw< strftime >;
use experimental qw< postderef signatures >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;
our $VERSION = '0.001';

use Dibs::Config ':all';
use Dibs::PacksList;
use Dibs::Docker;
use Dibs::Output;

use Exporter qw< import >;
our @EXPORT_OK = qw< main >;
our @EXPORT = ();

has _config => (is => 'ro', required => 1);
has _project_dir => (is => 'lazy');
has _dibspacks_for => (is => 'ro', default => sub { return {} });
has all_metadata => (is => 'ro', default => sub { return {} });

sub add_metadata ($self, %pairs) {
   my $md = $self->all_metadata;
   $md->%* = ($md->%*, %pairs);
   return $self;
}

sub metadata_for ($self, $key) { $self->all_metadata->{$key} // undef }

sub name ($self, $op) {
   if (defined($op) && defined(my $name = $self->dconfig($op, 'name'))) {
      return $name;
   }
   return $self->config('name');
}

sub config ($self, @path) {
   my $c = $self->_config;
   $c = $c->{shift @path} while defined($c) && @path;
   return $c;
}

sub dconfig ($self, @path) { $self->config(definitions => @path) }

sub _build__project_dir ($self) {
   return path($self->config('project_dir'))->absolute;
}

sub steps ($self) {$self->config('steps')->@*}

sub set_logger($self) {
   my $logger = $self->config('logger') // 'Sderr';
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

sub project_dir ($self, @subdirs) {
   my $pd = $self->_project_dir;
   return(@subdirs ? $pd->child(@subdirs) : $pd);
}

sub ensure_host_directories ($self) {
   my $pd = $self->project_dir;
   my $pds = $self->config('project_dirs');
   for my $name (CACHE, DIBSPACKS, ENVIRON, SRC) {
      my $subdir_name = $pds->{$name};
      $pd->child($subdir_name)->mkpath;
   }
   return;
}

sub dibspacks_for ($self, $x) {
   my $dfor = $self->_dibspacks_for;
   $dfor->{$x} //= Dibs::PacksList->new($x, $self->config);
   return $dfor->{$x}->list;
}

sub iterate_buildpacks ($self, $op) {
   # continue only if it makes sense...
   ouch 400, "no definitions for $op" unless defined $self->dconfig($op);
   my @dibspacks = $self->dibspacks_for($op) or return;

   my $args = $self->prepare_args($op);
   my $exception;
   try {
      DIBSPACK:
      for my $dp (@dibspacks) {
         my $name = $dp->name;
         ARROW_OUTPUT('+', "dibspack $name");

         $args->{env} = $self->coalesce_envs($dp, $op, $args);

         if ($dp->needs_fetch) {
            ARROW_OUTPUT('-', 'fetch dibspack');
            $dp->fetch;
         }

         if (!$dp->skip_detect && $dp->has_program('detect')) {
            ARROW_OUTPUT('-', "detect");
            if (! $self->call_detect($dp, $op, $args)) {
               OUTPUT('skip this dibspack');
               next DIBSPACK;
            }
         }

         ouch 500, (' ' x INDENT) . "error: dibspack $name cannot operate"
            unless $dp->has_program('operate');
         ARROW_OUTPUT('-', 'operate');
         $self->call_operate($dp, $op, $args);
      }
   }
   catch {
      $self->cleanup_tags($op, $args->{image});
      die $_; # rethrow
   };
   return $args->{image};
}

sub coalesce_envs ($self, $dp, $op, $args) {
   my $opc = $self->dconfig($op);
   return __merge_envs(
      $self->config(defaults => 'env'),
      $opc->{env},
      $dp->env,
      $self->all_metadata,
      {
         DIBS_FROM_IMAGE => $opc->{from},
         DIBS_WORK_IMAGE => $args->{image},
      },
   );
}

sub prepare_args ($self, $op) {
   my $opc = $self->dconfig($op);
   my $from = $opc->{from};
   my $image = Dibs::Docker::docker_tag($from, $self->target_name($op));
   return {
      image => $image,
      changes => $self->changes_for_commit($op),
      project_dir => $self->project_dir,
   };
}

sub changes_for_commit ($self, $op) {
   my $cfg = $self->dconfig($op);
   my %changes;
   for my $key (qw< entrypoint cmd >) {
      $changes{$key} = $cfg->{$key} if defined $cfg->{$key};
   }
   return \%changes;
}

sub cleanup_tags ($self, $op, @tags) {
   for my $tag (@tags) {
      try { Dibs::Docker::docker_rmi($tag) }
      catch { $log->error("failed to remove $tag") };
   }
   return;
}

sub additional_tags ($self, $op, $image, $new_tags) {
   return ($image) unless $new_tags;
   my @tags = $image;
   try {
      my $name = $self->name($op);
      for my $tag ($new_tags->@*) {
         my $dst = $tag =~ m{:}mxs ? $tag : "$name:$tag";
         Dibs::Docker::docker_tag($image, $dst);
         push @tags, $dst;
      }
   }
   catch {
      $self->cleanup_tags($op, @tags);
      die $_; # rethrow
   };
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

sub list_volumes ($self, $step) {
   my $pd = $self->project_dir;
   my $pds = $self->config('project_dirs');
   my $cds = $self->config('container_dirs');
   return map {
      my ($name, @mode) = ref($_) ? $_->@* : $_;
      [
         $pd->child($pds->{$name})->stringify,
         $cds->{$name},
         @mode
      ];
   } $self->config(volumes => $step)->@*;
}

sub call_detect ($self, $dp, $op, $args) {
   my $p = path($dp->container_path)->child('detect');
   my $opname = $self->dconfig($op, 'step') // $op;
   my ($exitcode) = Dibs::Docker::docker_run(
      $args->%*,
      keep    => 0,
      indent  => $dp->indent,
      volumes => [ $self->list_volumes('detect') ],
      command => [ $p->stringify, $opname, $self->list_dirs ],
   );
   return 1 if $exitcode == DETECT_OK;
   return 0 if $exitcode == DETECT_SKIP;

   my ($signal, $exit) = ($exitcode & 0xFF, $exitcode >> 8);
   ouch 500, "detect exited due to signal $signal" if $signal;
   ouch 500, "detect exited with $exit, interpreted as error";
}

sub call_operate ($self, $dp, $op, $args) {
   my $p = path($dp->container_path)->child('operate');
   my $opname = $self->dconfig($op, 'step') // $op;
   my ($exitcode, $cid, $out);
   try {
      ($exitcode, $cid, $out) = Dibs::Docker::docker_run(
         $args->%*,
         keep    => 1,
         indent  => $dp->indent,
         volumes => [ $self->list_volumes('operate') ],
         command => [ $p->stringify, $opname, $self->list_dirs ],
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

sub target_name ($self, $op) {
   join ':', $self->name($op), $self->metadata_for('DIBS_ID');
}

sub run_step ($self, $name) {
   my $image = $self->iterate_buildpacks($name);
   my $pc = $self->dconfig($name);
   return $pc->{keep}
      ? $self->additional_tags($name, $image, $pc->{tags})
      : $self->cleanup_tags($name, $image);
}

sub run ($self) {
   $self->set_logger;
   $self->set_run_metadata;
   $self->dump_configuration;
   $self->ensure_host_directories;

   my @tags_lists;
   return try {
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
      0;
   }
   catch {
      $self->cleanup_tags($_->@*) for reverse @tags_lists;
      $log->fatal(bleep);
      1;
   };
}

sub main (@as) { __PACKAGE__->new(_config => get_config(\@as))->run }

sub fetch ($config) {
   my $fc = $config->{fetch};
   return unless defined $fc; # undef -> use src directly, or nothing at all
   $fc = {
      type => 'git',
      origin => $fc,
   } if ! ref($fc) && $fc =~ m{\A(?: http s? | git | ssh )}mxs;
   ouch 500, 'most probably unimplemented'
      unless ref($fc) && $fc->{type} eq 'git';
   my $target = project_dir($config, $config->{project_dirs}{&SRC});
   require Dibs::Git;
   Dibs::Git::fetch($fc->{origin}, $target->stringify);
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
