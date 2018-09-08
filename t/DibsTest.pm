package DibsTest;
use strict;
use 5.024;
use Exporter 'import';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use File::chdir;

our @EXPORT = our @EXPORT_OK = qw<
   clean_environment
   directory_guard
   has_docker
   has_git
   init_git
>;


sub clean_environment { delete @ENV{(grep {/^DIBS_/} keys %ENV)} }

sub directory_guard ($path) { return DibsTest::FreezeDir->new($path) }

sub init_git ($path) {
   require Dibs::Run;
   local $CWD = $path->stringify;
   Dibs::Run::assert_command([qw< git init >]);
   Dibs::Run::assert_command([qw< git add . >]);
   Dibs::Run::assert_command([qw< git commit -m yay >]);
}

sub has_docker {
   require Dibs::Docker;
   return defined Dibs::Docker::docker_version();
}

sub has_git {
   require Dibs::Git;
   return defined Dibs::Git::git_version();
}

package DibsTest::FreezeDir;
use strict;
use 5.024;
use Path::Tiny;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use JSON::PP qw< encode_json decode_json >;

sub new ($package, $path) {
   $path = path($path);
   $path->exists or die "no path '$path'\n";
   my $flags_file = $path->child('flags.json');
   my ($flags, $do_cleanup);
   if ($flags_file->exists) {
      $flags = decode_json($flags_file->slurp_raw);
      $do_cleanup = 1;
   }
   else {
      $flags = {$flags_file => 1};
      $path->visit(
         sub { $flags->{$_} = 1 },
         {recurse => 1},
      );
      my $tmp = $flags_file->sibling($flags_file->basename . '.tmp');
      $tmp->spew_raw(encode_json($flags));
      $tmp->move($flags_file);
   }
   my $self = bless {path => $path, flags => $flags}, $package;
   $self->cleanup if $do_cleanup;
   return $self;
}

sub cleanup ($self) {
   my @deletes;
   my $flags = $self->{flags};
   $self->{path}->visit(
      sub { push @deletes, $_ unless $flags->{$_} },
      {recurse => 1},
   );
   for my $d (@deletes) {
      next unless $d->exists;
      if ($d->is_dir) {$d->remove_tree({safe => 0})}
      else            {$d->remove}
   }
}

sub DESTROY ($self) { $self->cleanup }

1;
