package Dibs;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use Pod::Find qw< pod_where >;
use Pod::Usage qw< pod2usage >;
use Getopt::Long qw< GetOptionsFromArray :config gnu_getopt >;
use Log::Any::Adapter;
use YAML::Tiny qw< LoadFile >;
use Path::Tiny qw< path cwd >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
our $VERSION = '0.001';

use constant DIBS_CONFIG => 'dibs.yml';
use constant OPTIONS => [
   ['project-dir|p=s', default => '.', help => 'project base directory'],
];

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
   pod2usage(%p2u, -message => 'Error: missing command', -exitval => 1)
     unless @ARGV;
   $config{optname($_)} = delete $config{$_} for keys %config;
   $config{args} = [$cmdline->@*];
   return \%config;
}

sub optname ($specish) { ($specish =~ s{[^-\w].*}{}rmxs) =~ s{-}{_}rgmxs }

sub get_config ($args, $defaults = undef) {
   $defaults //= {
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
      my $env_name = 'DIP_' . uc $name;
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
   say 'here!';
}

sub _merge { return {map {$_->%*} grep {defined} reverse @_} } # first wins

1;
__END__

=encoding utf8

=head1 NAME

dip - Docker Image Packer

=head1 VERSION

Ask the version number to the script itself, calling:

   shell$ dip --version


=head1 USAGE

   dip [--usage] [--help] [--man] [--version]

   dip [--project-dir|--project_dir|-p directory]
       command args...

=head1 EXAMPLES

   # fetch source into "src" subdirectory
   shell$ dip fetch-src



=head1 DESCRIPTION

Handle different phases of building software and pack it as a trimmed Docker
image.

=head2 Project Directory

All operations are supposed to be performed within the context of a base
directory for the whole project. This directory can be set via option
L</--project_dir>. By default it is the current directory.

The project directory MUST contain a configuration file for the project,
called C<dpi.yml>.

=head1 OPTIONS

C<dip> supports some command line options. Some of them are I<meta>, in
the sense that their goal is to provide information about C<dip> itself;
other options are actually used by C<dip> to do its intended job.

=head2 Meta-Options

The following I<meta-options> allow getting more info about C<dip>
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

The following options are supported by C<dip> as part of its mission:

=over

=item project_dir

=item --project-dir

=item -p

   $ dip --project-dir directory

set the base directory of the project. All files and directories are referred
to that directory. Defaults to the current directory.

=back

=head1 DIAGNOSTICS

Whatever fails will complain quite loudly.

=head1 CONFIGURATION AND ENVIRONMENT

C<dip> can be configured in multiple ways. The following is a list of
where configurations are taken, in order of precedence (alternatives
higher in the list take precedence over those below them):

=over

=item *

command line options;

=item *

environment variables, in the form C<DPI_XXXX> where C<XXXX> corresponds
to the command line option name (only for L</Real Options>, first
alternative for each of them), with initial hypens removed, intermediate
hyphens turned into underscores and all letters turned uppercase. For
example, option L</--project_dir> corresponds to environment variable
C<DPI_PROJECT_DIR>;

=item *

configuration file C<dip.yaml> as mandatorily found in the L</Project
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
