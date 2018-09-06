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

use constant BIN         => 'bin';
use constant CACHE       => 'cache';
use constant DIBSPACKS   => 'dibspacks';
use constant DPFILE      => '.dibspacks';
use constant EMPTY       => 'empty';
use constant ENVIRON     => 'env';
use constant GIT         => 'git';
use constant INSIDE      => 'inside';
use constant PROJECT     => 'project';
use constant IMMEDIATE   => 'immediate';
use constant SRC         => 'src';
use constant DETECT_OK   => ((0 << 8) | 0);
use constant DETECT_SKIP => ((100 << 8) | 0);
use constant INDENT      => 7;
use constant ALIEN_PROJECT_DIR => '.';
use constant LOCAL_PROJECT_DIR => 'dibs';
use constant CONFIG_FILE       => 'dibs.yml';

use constant DEFAULTS => {
   project_dirs =>
     {CACHE, 'cache', DIBSPACKS, 'dibspacks', ENVIRON, 'env', SRC, 'src',
     EMPTY, 'empty'},
   container_dirs => {
      CACHE,   '/tmp/cache', DIBSPACKS, '/tmp/dibspacks',
      ENVIRON, '/tmp/env',   SRC,       '/tmp/src',
   },
   volumes => [CACHE, [ENVIRON, 'ro'], [DIBSPACKS, 'ro'], SRC, [EMPTY, 'ro']],
   dibspack_dirs => [SRC, CACHE, ENVIRON],
};
use constant OPTIONS => [
   [
      'alien|A!',
      default => undef,
      help => 'package some external project, work in current directory',
   ],
   [
      'config-file|config|c=s',
      default => CONFIG_FILE,
      help    => 'name of configfile'
   ],
   [
      'origin|O=s',
      default => undef,
      help    => 'get src from specific "location"',
   ],
   [
      'host-project-dir|H=s',
      default => undef,
      help    => 'project base dir (dind-like)'
   ],
   [
      'local|l!',
      default => undef,
      help    => 'change convention for directories layout, work in .dibs',
   ],
   [
      'change-dir|C=s',
      default => undef,
      help    => 'change to dir as current directory',
   ],
   ['project-dir|p=s', default => LOCAL_PROJECT_DIR, help => 'project base directory'],
   ['#steps'],
];
use constant ENV_PREFIX => 'DIBS_';

use Exporter qw< import >;
our %EXPORT_TAGS = (
   constants => [
      qw<
        BIN CACHE DIBSPACKS DPFILE EMPTY ENVIRON GIT IMMEDIATE
        INSIDE PROJECT SRC
        DETECT_OK DETECT_SKIP
        INDENT
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
      grep {substr($_, 0, 1) ne '#'} map { $_->[0] } $optspecs->@*,
   ) or _pod2usage(-exitval => 1);
   if ($config{version}) {
      my $version = 'unknown';
      $version = main::version() if main->can('version');
      _pod2usage(-message => $version, -sections => ' ')
   }
   _pod2usage() if $config{usage};
   _pod2usage(-sections => 'USAGE|EXAMPLES|OPTIONS')
     if $config{help};
   _pod2usage(-verbose => 2) if $config{man};
   $config{optname($_)} = delete $config{$_} for keys %config;
   $config{steps} = [map { split m{[,\s]}mxs } $cmdline->@*]
     if scalar $cmdline->@*;
   return \%config;
} ## end sub get_cmdline

sub optname ($specish) {
   $specish =~ s{\A\#}{}mxs;
   $specish =~ s{[^-\w].*}{}mxs;
   $specish =~ s{-}{_}gmxs;
   return $specish;
}

sub add_config_file ($sofar, $cnfp) {
   ouch 400, 'no configuration file found' unless $cnfp->exists;
   my $cnffile = LoadFile($cnfp);

   my ($frozen, $cmdline, $env, $defaults) # revive these variables
      = $sofar->{_sources}->@{qw< frozen cmdline environment defaults >};
   
   # save a few values that are frozen by now
   $frozen->{has_cloned} = $sofar->{has_cloned};
   $frozen->{config_file} = $cnfp;

   # configurations from the file must have higher precedence with respect
   # to the defaults. The "frozen" stuff takes highest precedence anyway.
   my $overall = _merge($frozen, $cmdline, $env, $cnffile, $defaults);

   # some configurations have mutual exclusions
   my $is_alien = $sofar->{alien};
   my $is_local = $sofar->{local};
   my $is_development = $sofar->{development};
   my $origin   = $overall->{origin} // undef;
   _pod2usage(
      -message => 'cannot have both origin and local configurations',
      -exitval => 1,
   ) if $is_local && defined $origin;

   # now I can set origin... it will be ignored by local and used by others
   $origin //= '' if $is_development;
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
}

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
   }

   # some configurations have mutual exclusions
   my ($is_alien, $is_local) = $sofar->@{qw< alien local >};
   _pod2usage(
      -message => 'alien and local are mutually exclusive',
      -exitval => 1,
   ) if $is_alien && $is_local;

   # "frozen" stuff is frozen here and cannot be otherwise overridden
   my %frozen = (
      alien => $is_alien,
      local => $is_local,
      development => (!($is_alien || $is_local)),
   );

   my $project_dir = $sofar->{project_dir} // undef;
   my @searchpaths;
   if ($is_alien) {
      $project_dir //= ALIEN_PROJECT_DIR;  # otherwise no point
      @searchpaths = ($project_dir);
   }
   else { # local mode, development mode
      $project_dir //= LOCAL_PROJECT_DIR;  # otherwise no point
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
      }
   }

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
} ## end sub get_config

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
   my $variables = $overall->{defaults}{variables} // [];
   for my $var ($variables->@*) {
      next unless (ref($var) eq 'HASH') && (scalar(keys $var->%*) == 1);
      my ($key, $value) = $var->%*;
      next unless ($key eq 'function') && (ref($value) eq 'ARRAY');
      my $function = shift $value->@* // 'undefined';
      state $cb_for = {
         join => sub { my $s = shift; join $s, @_ },
      };
      ouch 400, "unhandled expansion function $function"
         unless exists $cb_for->{$function};
      $var->{$key} = $cb_for->{$function}->($value->@*);
   }
}

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
