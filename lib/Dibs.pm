package Dibs;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use Pod::Find qw< pod_where >;
use Pod::Usage qw< pod2usage >;
use Getopt::Long qw< GetOptionsFromArray :config gnu_getopt >;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use YAML::Tiny qw< LoadFile >;
use Path::Tiny qw< path cwd >;
use Data::Dumper;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use POSIX qw< strftime >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
our $VERSION = '0.001';

use Dibs::PacksList;
use Dibs::Docker;

use constant DEFAULTS => {
   project_dibspacks_dir   => 'dibspacks',
   project_src_dir         => 'src',
   project_cache_dir       => 'cache',
   project_env_dir         => 'env',
   container_dibspacks_dir => '/tmp/dibspacks',
   container_src_dir       => '/tmp/src',
   container_cache_dir     => '/tmp/cache',
   container_env_dir       => '/tmp/env',
};
use constant DIBS_CONFIG => 'dibs.yml';
use constant OPTIONS => [
   ['build-dibspacks|build-dibspack=s@',  help => 'list of dibspack for building'],
   ['bundle-dibspacks|bundle-dibspack=s@', help => 'list of dibspacks for bundling'],
   ['project-dir|p=s', default => '.', help => 'project base directory'],
];
use constant ENV_PREFIX => 'DIBS_';

use Exporter qw< import >;
our @EXPORT_OK = qw< main >;
our @EXPORT = ();

sub get_cmdline ($optspecs = OPTIONS, $cmdline = []) {
   my %p2u = (
      -exitval => 0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
      -sections => 'USAGE',
      -verbose => 99,
   );
   my %config;
   GetOptionsFromArray(
      $cmdline,
      \%config,
      qw< usage! help! man! version!  >,
      map { $_->[0] } $optspecs->@*,
   ) or pod2usage(%p2u, -exitval => 1);
   pod2usage(%p2u, -message => $VERSION, -sections => ' ')
     if $config{version};
   pod2usage(%p2u) if $config{usage};
   pod2usage(%p2u, -sections => 'USAGE|EXAMPLES|OPTIONS')
     if $config{help};
   pod2usage(%p2u, -verbose => 2) if $config{man};
   #pod2usage(%p2u, -message => 'Error: missing command', -exitval => 1)
   #  unless @ARGV;
   $config{optname($_)} = delete $config{$_} for keys %config;
   $config{args} = [$cmdline->@*];
   return \%config;
}

sub optname ($specish) { ($specish =~ s{[^-\w].*}{}rmxs) =~ s{-}{_}rgmxs }

sub get_config ($args, $defaults = undef) {
   $defaults //= {
      DEFAULTS->%*,
      map {
         my ($name, %opts) = $_->@*;
         $name =~ s{[^-\w].*}{}mxs;
         $name =~ s{-}{_}gmxs;
         exists($opts{default}) ? ($name => $opts{default}) : ();
      } OPTIONS->@*
   };
   my $env = get_environment(OPTIONS, {%ENV});
   my $cmdline = get_cmdline(OPTIONS, $args);
   my $sofar = _merge($cmdline, $env, $defaults);
   my $project_dir = path($sofar->{project_dir});
   my $cnffile = LoadFile($project_dir->child(DIBS_CONFIG)->stringify);
   my $overall = _merge($cmdline, $env, $cnffile, $defaults);
   $overall->{project_dir} = $project_dir;

   # adjust buildpacks
   for my $name (qw< build bundle >) {
      my $cename = $name . '_dibspacks';
      next unless exists $overall->{$cename};
      $overall->{$name}{dibspacks} = delete $overall->{$cename};
   }
   $overall->{dibspacks} = Dibs::PacksList->create($overall);

   return {
      $overall->%*,
      _sources => {
         overall     => $overall,
         cmdline     => $cmdline,
         environment => $env,
         cnffile     => $cnffile,
         defaults    => $defaults,
      },
   };
}

sub get_environment ($optspecs = OPTIONS, $env = {%ENV}) {
   my %config;
   for my $option ($optspecs->@*) {
      my $name = optname($option->[0]);
      my $env_name = ENV_PREFIX . uc $name;
      $config{$name} = $env->{$env_name} if exists $env->{$env_name};
   }
   return \%config;
}

sub set_logger($logger) {
   my @logger = ref($logger) ? $logger->@* : $logger;
   Log::Any::Adapter->set(@logger);
}

sub main (@args) {
   my $config = get_config(\@args);
   set_logger($config->{logger} // 'Stderr');
   set_run_metadata($config);
   local $Data::Dumper::Indent = 1;
   $log->debug(Dumper $config);
   ensure_host_directories($config);
   fetch($config);
   build($config);
   my @tags = bundle($config);
   say for @tags;
}

sub _merge { return {map {$_->%*} grep {defined} reverse @_} } # first wins

sub ensure_host_directories ($config) {
   my $pd = path($config->{project_dir});
   for my $name (qw< dibspacks src cache env >) {
      my $sd = $pd->child($config->{"project_${name}_dir"});
      $sd->mkpath;
   }
}

sub fetch ($config) {
   my $fc = $config->{fetch};
   return unless defined $fc; # undef -> use src directly
   $fc = {
      type => 'git',
      origin => $fc,
   } if ! ref($fc) && $fc =~ m{\A(?: http s? | git | ssh )}mxs;
   ouch 500, 'most probably unimplemented'
      unless ref($fc) && $fc->{type} eq 'git';
   my $target = path($config->{project_dir})->child($config->{project_src_dir});
   require Dibs::Git;
   Dibs::Git::fetch($fc->{origin}, $target->stringify);
}

sub set_run_metadata ($config) {
   $config->{run}{metadata} = {
      DIBS_ID => strftime("%Y%m%d-%H%M%S-$$", gmtime),
   };
}

sub target_name ($config) {
   return join ':', $config->{name}, $config->{run}{metadata}{DIBS_ID};
}

sub _detect ($config, $dp, $args, $opts) {
   my $bin_dir = path($dp->container_path)->child('bin');
   my ($exitcode) = Dibs::Docker::docker_run(
      $args->%*,
      keep    => 0,
      volumes => [ list_volumes($config, $opts->{detect_volumes}->@*) ],
      command => [ $bin_dir->child("$opts->{operation}-detect")->stringify,
         list_dirs($config, $opts->{detect_dirs}->@*) ],
   );
   return $exitcode == 0;
}

sub _operate ($config, $dp, $args, $opts) {
   my $bin_dir = path($dp->container_path)->child('bin');
   my ($exitcode, $cid, $out);
   try {
      ($exitcode, $cid, $out) = Dibs::Docker::docker_run(
         $args->%*,
         keep    => 1,
         volumes => [ list_volumes($config, $opts->{op_volumes}->@*) ],
         command => [ $bin_dir->child($opts->{operation})->stringify,
            list_dirs($config, $opts->{op_dirs}->@*) ],
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

sub _docker_commit_changes ($config, $opts) {
   my $cfg = $config->{$opts->{operation}};
   my %changes;
   for my $key (qw< entrypoint cmd >) {
      $changes{$key} = $cfg->{$key} if defined $cfg->{$key};
   }
   return \%changes;
}

sub _prepare_args ($config, $opts) {
   my $from = $config->{$opts->{operation}}{from};
   my $image = Dibs::Docker::docker_tag($from, target_name($config));
   return {
      env => merge_envs(
         $config->{$opts->{operation}}{env},
         $config->{run}{metadata},
         ($opts->{env} // {}),
         {
            DIBS_FROM_IMAGE => $from,
            DIBS_WORK_IMAGE => $image,
         },
      ),
      image => $image,
      changes => _docker_commit_changes($config, $opts),
      project_dir => $config->{project_dir},
   };
}

sub cleanup_tags (@tags) {
   for my $tag (@tags) {
      try { Dibs::Docker::docker_rmi($tag) }
      catch { $log->error("failed to remove $tag") };
   }
   return;
}

sub iterate_buildpacks ($config, $opts) {
   my $op = $opts->{operation};
   my $args = _prepare_args($config, $opts);
   my $exception;
   try {
      DIBSPACK:
      for my $dp ($config->{dibspacks}->list_for($op)) {
         my $spec = $dp->specification;
         $dp->fetch;

         $log->info("$op-detect $spec");
         if (! _detect($config, $dp, $args, $opts)) {
            $log->info("skipping dibspack $spec");
            next DIBSPACK;
         }

         $log->info("$op        $spec");
         _operate($config, $dp, $args, $opts);
         $log->info("$op        $spec completed successfully");
      }
   }
   catch {
      cleanup_tags($args->{image});
      die $_; # rethrow
   };
   return $args->{image};
}

sub additional_tags ($config, $image, $new_tags) {
   return ($image) unless $new_tags;
   my @tags = $image;
   try {
      my $name = $config->{name};
      for my $tag ($new_tags->@*) {
         my $dst = $tag =~ m{:}mxs ? $tag : "$name:$tag";
         Dibs::Docker::docker_tag($image, $dst);
         push @tags, $dst;
      }
   }
   catch {
      cleanup_tags(@tags);
      die $_; # rethrow
   };
   return @tags;
}

sub build ($config) {
   my $bc = $config->{build};
   my $image = iterate_buildpacks($config,
      {
         operation      => 'build',
         detect_volumes => [qw< dibspacks:ro src:ro cache:ro env:ro >],
         detect_dirs    => [qw< src cache env >],
         op_volumes     => [qw< dibspacks:ro src    cache    env:ro >],
         op_dirs        => [qw< src cache env >],
         env            => {},
      },
   );
   return cleanup_tags($image);
}

sub bundle ($config) {
   my $bc = $config->{bundle};
   my $image = iterate_buildpacks($config,
      {
         operation      => 'bundle',
         detect_volumes => [qw< dibspacks:ro src:ro cache:ro env:ro >],
         detect_dirs    => [qw< src cache env >],
         op_volumes     => [qw< dibspacks:ro src:ro cache    env:ro >],
         op_dirs        => [qw< src cache env >],
         env            => {},
      },
   );
   return additional_tags($config, $image, $bc->{tags});
}

sub merge_envs (@envs) {
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

sub list_dirs ($config, @names) {
   return map { $config->{'container_' . $_ . '_dir'} } @names;
}

sub list_volumes ($config, @specs) {
   my $pd = path($config->{project_dir})->absolute;
   return map {
      my ($name, @mode) = split /:/, $_, 2;
      [
         $pd->child($config->{'project_' . $name . '_dir'})->stringify,
         $config->{'container_' . $name . '_dir'},
         @mode
      ];
   } @specs;
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
