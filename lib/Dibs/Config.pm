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
use constant DEFAULT_PROJECT_DIR => '.';
use constant LOCAL_PROJECT_DIR   => '.dibs';
use constant CONFIG_FILE         => 'dibs.yml';

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
      'config-file|config|c=s',
      default => CONFIG_FILE,
      help    => 'name of configfile'
   ],
   [
      'host-project-dir|H=s',
      default => undef,
      help    => 'project base dir (dind-like)'
   ],
   [
      'local|l!',
      default => undef, # might just as well leave it out
      help    => 'change convention for directories layout',
   ],
   [
      'change-dir|C=s',
      default => undef,
      help    => 'change to dir as current directory',
   ],
   ['project-dir|p=s', default => DEFAULT_PROJECT_DIR, help => 'project base directory'],
   ['steps|step|s=s@', help => 'steps to execute'],
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
   functions => [qw< get_config yaml_boolean >],
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
      -input    => pod_where({-inc => 1}, __PACKAGE__),
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
      map { $_->[0] } $optspecs->@*,
   ) or _pod2usage(-exitval => 1);
   _pod2usage(-message => $VERSION, -sections => ' ')
     if $config{version};
   _pod2usage() if $config{usage};
   _pod2usage(-sections => 'USAGE|EXAMPLES|OPTIONS')
     if $config{help};
   _pod2usage(-verbose => 2) if $config{man};
   $config{optname($_)} = delete $config{$_} for keys %config;
   $config{args} = [$cmdline->@*];
   $config{steps} = [map { split m{[,\s]}mxs } $config{steps}->@*]
     if exists $config{steps};
   return \%config;
} ## end sub get_cmdline

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

   # see if it's a "local" run
   if ($sofar->{local}) {
      $defaults->{project_dir} = LOCAL_PROJECT_DIR
         unless defined($sofar->{project_dir}); # otherwise no point

      # force absolute version of config_file path if it exists relative to
      # the current directory, to override search in project dir. This is
      # valid only because `local` was set.
      my $cnfp = path($sofar->{config_file} // CONFIG_FILE)->absolute;
      $sofar->{config_file} = $cnfp if $cnfp->exists;
   }

   # now merge everything, including defaults. This will definitely set
   # where the project dir is located and load the configuration file from
   # there... maybe
   $sofar          = _merge($sofar, $defaults);
   my $project_dir = path($sofar->{project_dir});

   # now look for a configuration file. Absolute paths are taken as-is,
   # relative ones are referred to the project directory
   my $cnfp = path($sofar->{config_file});
   $cnfp = $cnfp->absolute($project_dir) if $cnfp->is_relative;
   my $cnffile = LoadFile($cnfp);

   # configurations from the file must have higher precedence with respect
   # to the defaults. We will keep a couple things anyway.
   my $overall = _merge($cmdline, $env, $cnffile, $defaults);
   $overall->{project_dir} = $project_dir;
   $overall->{config_file} = $cnfp;

   # adjust definitions
   adjust_definitions($overall);

   # now return everything! No anticipation of performance issues here...
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
