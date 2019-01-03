package Dibs::Config;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use Pod::Find qw< pod_where >;
use Pod::Usage qw< pod2usage >;
use Getopt::Long qw< GetOptionsFromArray :config gnu_getopt >;
use Log::Any qw< $log >;
use YAML::XS qw< LoadFile >;
use Path::Tiny qw< path cwd >;
use Data::Dumper;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use POSIX qw< strftime >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
our $VERSION = '0.001';

use constant BIN               => 'bin';
use constant CACHE             => 'cache';
use constant C_CACHE           => '/tmp/cache';
use constant H_CACHE           => 'cache';
use constant DEFAULTS_FIELD    => 'defaults';
use constant DEFINITIONS       => 'definitions';
use constant FRAME             => 'frame';
use constant LOG               => 'log';
use constant FROM              => 'from';
use constant STEPS             => 'steps';
use constant DPFILE            => '.dibsstrokes';
use constant HTTP              => 'http';
use constant WORKFLOW          => 'workflow';
use constant ENVIRON           => 'env';
use constant C_ENVIRON         => '/tmp/env';
use constant H_ENVIRON         => 'env';
use constant ENVILE            => 'envile';
use constant C_ENVILE          => '/tmp/envile';
use constant H_ENVILE          => 'envile';
use constant GIT               => 'git';
use constant INSIDE            => 'inside';
use constant OPERATE           => 'operate';
use constant PACK              => 'pack';
use constant PACKS             => 'packs';
use constant PACK_HOST_ONLY    => 'hostpack';
use constant H_PACK_HOST_ONLY  => 'auto/host-only';
use constant PACK_DYNAMIC      => 'autopack';
use constant C_PACK_DYNAMIC    => '/tmp/autopack';
use constant H_PACK_DYNAMIC    => 'auto/open';
use constant PACK_STATIC       => 'pack';
use constant C_PACK_STATIC     => '/tmp/pack';
use constant H_PACK_STATIC     => 'pack';
use constant PROJECT           => 'project';
use constant IMMEDIATE         => 'immediate';
use constant SKETCH            => 'sketch';
use constant SRC               => 'src';
use constant C_SRC             => '/tmp/src';
use constant STROKE            => 'stroke';
use constant DETECT_OK         => ((0 << 8) | 0);
use constant DETECT_SKIP       => ((100 << 8) | 0);
use constant INDENT            => 7;
use constant ALIEN_PROJECT_DIR => '.';
use constant LOCAL_PROJECT_DIR => 'dibs';
use constant VOLUMES           => 'volumes';
use constant CONFIG_FILE       => 'dibs.yml';

use constant DEFAULTS => {
   logger         => [qw< Stderr log_level info >],
   zone_specs_for => {
      CACHE,
      {
         container_base => C_CACHE,
         host_base      => H_CACHE,
         writeable      => 1,
      },
      ENVILE,
      {
         container_base => C_ENVILE,
         host_base      => H_ENVILE,
      },
      ENVIRON,
      {
         container_base => C_ENVIRON,
         host_base      => H_ENVIRON,
      },
      PACK_DYNAMIC,
      {
         container_base => C_PACK_DYNAMIC,
         host_base      => H_PACK_DYNAMIC,
      },
      PACK_STATIC,
      {
         container_base => C_PACK_STATIC,
         host_base      => H_PACK_STATIC,
      },
      SRC,
      {
         container_base => '/tmp/src',
         host_base      => 'src',
         writeable      => 1,
      },
      INSIDE,
      {
         container_base => '/',
         host_base      => undef,
      },
      PACK_HOST_ONLY,
      {
         container_base => undef,
         host_base => PACK_HOST_ONLY,
      },
   },
   zone_names_for => {
      &VOLUMES  => [SRC, CACHE, ENVILE, ENVIRON, PACK_DYNAMIC, PACK_STATIC],
   },
};
use constant OPTIONS => [
   [
      'alien|A!',
      default => undef,
      help => 'package some external project, work in current directory',
   ],
   [
      'change-dir|C=s',
      default => undef,
      help    => 'change to dir as current directory',
   ],
   [
      'config-file|config|c=s',
      default => CONFIG_FILE,
      help    => 'name of configfile'
   ],
   [
      'dirty|dirty-origin-is-ok|D!',
      default => undef,
      help    => 'accept a dirty origin (strongly discouraged)',
   ],
   [
      'host-project-dir|H=s',
      default => undef,
      help    => 'project base dir (dind-like)'
   ],
   [
      'loglevel|l=s',
      default => 'INFO',
      help => 'level of verbosity in logging',
   ],
   [
      'origin|O=s',
      default => undef,
      help    => 'get src from specific "location"',
   ],
   [
      'project-dir|p=s',
      default => LOCAL_PROJECT_DIR,
      help    => 'project base directory'
   ],
   [
      'verbose|v!',
      DEFAULT => undef,
      help => 'be more verbose identifying elements',
   ],
   ['#do'],
];
use constant ENV_PREFIX => 'DIBS_';

use Exporter qw< import >;
our %EXPORT_TAGS = (
   constants => [
      qw<
        BIN CACHE DPFILE ENVIRON GIT IMMEDIATE
        ENVILE INSIDE PROJECT SRC OPERATE DEFAULTS_FIELD
        DEFINITIONS DETECT_OK DETECT_SKIP STEPS WORKFLOW HTTP
        INDENT DEFAULTS FRAME
        SKETCH STROKE LOG FROM VOLUMES PACK
        PACK_HOST_ONLY PACK_STATIC PACK_DYNAMIC
        >
   ],
   functions => [qw< get_config_cmdenv add_config_file yaml_boolean >],
);
our @EXPORT_OK = do {
   my %flag;
   grep { $flag{$_}++ < 1 } map { $_->@* } values %EXPORT_TAGS;
};
$EXPORT_TAGS{all} = [@EXPORT_OK];
our @EXPORT = ();

sub _pod2usage {
   pod2usage(
      -exitval  => 0,
      -sections => 'USAGE',
      -verbose  => 99,
      @_
   );
} ## end sub _pod2usage

sub get_cmdline ($optspecs = OPTIONS, $cmdline = []) {
   my %config;
   GetOptionsFromArray(
      $cmdline, \%config,
      qw< usage! help! man! version!  >,
      grep { substr($_, 0, 1) ne '#' } map { $_->[0] } $optspecs->@*,
   ) or _pod2usage(-exitval => 1);
   if ($config{version}) {
      my $version = 'unknown';
      $version = main::version() if main->can('version');
      _pod2usage(-message => $version, -sections => ' ');
   }
   _pod2usage() if $config{usage};
   _pod2usage(-sections => 'USAGE|EXAMPLES|OPTIONS')
     if $config{help};
   _pod2usage(-verbose => 2) if $config{man};
   $config{optname($_)} = delete $config{$_} for keys %config;

   my $logger = $config{logger} // [DEFAULTS->{logger}->@*];
   if (ref($logger) ne 'ARRAY') {
      $logger = [
         map {s{%([a-fA-F0-9]{2})}{chr hex $1}xgerms}
         split m{\s+}mxs, $logger
      ];
   }
   push $logger->@*, 'log_level', $config{loglevel}
      if defined $config{loglevel};
   $config{logger} = $logger;

   $config{do} = ['default'];
   $config{do} = [map { split m{[,\s]}mxs } $cmdline->@*]
     if scalar $cmdline->@*;
   return \%config;
} ## end sub get_cmdline

sub optname ($specish) {
   $specish =~ s{\A\#}{}mxs;
   $specish =~ s{[^-\w].*}{}mxs;
   $specish =~ s{-}{_}gmxs;
   return $specish;
} ## end sub optname ($specish)

sub add_config_file ($sofar, $cnfp) {
   ouch 400, 'no configuration file found' unless $cnfp->exists;
   my $cnffile = LoadFile($cnfp);

   my ($frozen, $cmdline, $env, $defaults)    # revive these variables
     = $sofar->{_sources}->@{qw< frozen cmdline environment defaults >};

   # save a few values that are frozen by now
   $frozen->{has_cloned}  = $sofar->{has_cloned};
   $frozen->{config_file} = $cnfp;

   # configurations from the file must have higher precedence with respect
   # to the defaults. The "frozen" stuff takes highest precedence anyway.
   my @contributors = ($frozen, $cmdline, $env, $cnffile, $defaults);
   my $overall = _merge(@contributors);
   for my $key (qw< zone_specs_for >) {
      $overall->{$key} = _merge(
         map { exists($_->{$key}) ? $_->{$key} : () } @contributors
      );
   }

   my $origin = $overall->{origin} // undef;
   $origin //= '' if $sofar->{development};
   $overall->{origin} = cwd() . $origin
     if defined($origin) && $origin =~ m{\A (?: \#.+ | \z )}mxs;

   # adjust definitions and variables (that are "expanded" if needed)
   adjust_definitions($overall);
   adjust_default_variables($overall);

   # now return everything! No anticipation of performance issues here...
   return {
      $overall->%*,
      _sources => {
         overall     => $overall,
         cmdline     => $cmdline,
         environment => $env,
         frozen      => $frozen,
         cnffile     => $cnffile,
         defaults    => $defaults,
      },
   };
} ## end sub add_config_file

sub get_config_cmdenv ($args, $defaults = undef) {
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

   # first step merge command line and environment, leave defaults out
   # because they might have to be changed depending on options
   my $sofar = _merge($cmdline, $env);

   # honor request to change directory as early as possible
   if (defined $sofar->{change_dir}) {
      if (length($sofar->{change_dir}) && $sofar->{change_dir} ne '.') {
         chdir $sofar->{change_dir}
           or ouch 400, "unable to go in '$sofar->{change_dir}': $!";
      }
   } ## end if (defined $sofar->{change_dir...})

   # "frozen" stuff is frozen here and cannot be otherwise overridden
   my $is_alien = $sofar->{alien};
   my %frozen = (
      alien       => $is_alien,
      development => (!$is_alien),
   );

   my $project_dir = $sofar->{project_dir} // undef;
   my @searchpaths;
   if ($is_alien) {
      $project_dir //= ALIEN_PROJECT_DIR;    # otherwise no point
      @searchpaths = ($project_dir);
   }
   else {                                    # local mode, development mode
      $project_dir //= LOCAL_PROJECT_DIR;    # otherwise no point
      @searchpaths = (cwd(), $project_dir);
   }
   $frozen{project_dir} = path($project_dir);

   my $cnfp = path($sofar->{config_file} // CONFIG_FILE);
   if ($cnfp->is_relative) {
      for my $searchpath (@searchpaths) {
         my $candidate = path($searchpath)->child($cnfp)->absolute;
         next unless $candidate->exists;
         $sofar->{config_file} = $candidate;
         last;
      } ## end for my $searchpath (@searchpaths)
   } ## end if ($cnfp->is_relative)

   # now merge everything, including defaults. This will definitely set
   # where the project dir is located and load the configuration file from
   # there... maybe
   return {
      _merge(\%frozen, $sofar, $defaults)->%*,
      _sources => {
         frozen      => \%frozen,
         cmdline     => $cmdline,
         environment => $env,
         defaults    => $defaults,
      },
   };
} ## end sub get_config_cmdenv

sub yaml_boolean ($v) {
   return 0 unless defined $v;
   state $yb = {
      (
         map { $_ => 0 }
           qw<
           n  N  no     No     NO
           false  False  FALSE
           off    Off    OFF
           >
      ),
      (
         map { $_ => 1 }
           qw<
           y  Y  yes    Yes    YES
           true   True   TRUE
           on     On     ON
           >
      ),
   };
   return $yb->{$v} // undef;
} ## end sub yaml_boolean ($v)

sub adjust_definitions ($overall) {

   # "keep" is a boolean FIXME can we get rid of this with YAML::XS?
   while (my ($k, $d) = each $overall->{definitions}->%*) {
      defined($d->{keep} = yaml_boolean($d->{keep}))
        or ouch 400, "definition for $k: 'keep' is not a boolean\n";
   }
} ## end sub adjust_definitions ($overall)

sub adjust_default_variables ($overall) {
   my $variables = $overall->{variables}
      // $overall->{defaults}{variables} // [];
   for my $var ($variables->@*) {
      next unless (ref($var) eq 'HASH') && (scalar(keys $var->%*) == 1);
      my ($key, $value) = $var->%*;
      next unless ($key eq 'function') && (ref($value) eq 'ARRAY');
      my $function = shift $value->@* // 'undefined';
      state $cb_for = {join => sub { my $s = shift; join $s, @_ },};
      ouch 400, "unhandled expansion function $function"
        unless exists $cb_for->{$function};
      $var->{$key} = $cb_for->{$function}->($value->@*);
   } ## end for my $var ($variables...)
} ## end sub adjust_default_variables ($overall)

sub get_environment ($optspecs = OPTIONS, $env = {%ENV}) {
   my %config;
   for my $option ($optspecs->@*) {
      my $name     = optname($option->[0]);
      my $env_name = ENV_PREFIX . uc $name;
      $config{$name} = $env->{$env_name} if exists $env->{$env_name};
   }
   return \%config;
} ## end sub get_environment

sub _merge {
   return {map { $_->%* } grep { defined } reverse @_};
}    # first wins

1;
__END__

=encoding utf8

=head1 NAME

Dibs::Config - Configuration assembling for Dibs

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
