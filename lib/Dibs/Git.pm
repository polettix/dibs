package Dibs::Git;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use File::chdir;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Run qw< assert_command assert_command_out >;
use Dibs::Output;

sub checkout_ref ($path, $ref = 'master') {
   local $CWD = path($path)->stringify;
   assert_command [qw< git checkout >, $ref];
   my $out = assert_command_out [qw< git branch >];
   my ($active) = $out =~ m{^ \* \s* (.*?) $}mxs;
   return if substr($active, 0, 1) eq '(';    # detached head, exact point
   assert_command [qw< git merge >, "origin/$ref"];
   return;
} ## end sub checkout_ref

sub clone ($origin, $dir) {
   $dir = path($dir)->stringify;
   assert_command [qw< git clone >, $origin, $dir];
   return;
}

sub _current_origin ($path) {
   local $CWD = path($path)->stringify;
   my $out = assert_command_out [qw< git remote get-url origin >];
   return $out =~ s{\s+\z}{}rmxs;
}

sub fetch ($uri, $path) {
   my $ref = $uri =~ m{\#}mxs ? $uri =~ s{\A.*\#}{}rmxs : 'master';
   _fetch($uri =~ s{\#.*}{}rmxs, $path);
   checkout_ref($path, $ref);
}

sub _fetch ($origin, $dir) {
   $dir = path($dir);
   return clone($origin, $dir) unless $dir->child('.git')->exists;

   my $current_origin = _current_origin($dir);
   if ($current_origin ne $origin) {
      OUTPUT('changed origin, re-cloning');
      $dir->remove_tree({safe => 0});
      return clone($origin, $dir);
   }

   local $CWD = $dir->stringify;
   assert_command [qw< git fetch origin >];

   return $dir;
} ## end sub _fetch

sub git_version { eval { assert_command_out([qw< git --version >]) } }

sub is_dirty ($uri) {
   return eval { # exceptions taken as "not dirty"
      return if $uri =~ m{\A [a-zA-Z]\w :// }mxs;
      my ($origin, $ref) = split m{\#}mxs, $uri, 2;
      my $path = path($origin)->stringify;
      return unless -d $path;

      # examine the (local) origin. Bare repos are OK by definition
      local $CWD = $path;
      my $is_bare = assert_command_out [qw< git config --local --get core.bare >];
      return if lc($is_bare) eq 'true';

      # an exact reference is OK as long as it's not the current branch
      my $branches = assert_command_out [qw< git branch >];
      my ($current_branch) = $branches =~ m{^\* \s+ (.*?) \s*$}mxs;
      return if length($ref // '') && $ref ne $current_branch;

      # check for repo's dirty state
      my $dirt = assert_command_out [qw< git status --porcelain >];
      return length($dirt // '');
   };
}

1;
__END__
