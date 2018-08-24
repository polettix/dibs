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
}

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

sub checkout_ref ($path, $ref = 'master') {
   local $CWD = path($path)->stringify;
   assert_command [qw< git checkout >, $ref];
   my $out = assert_command_out [qw< git branch >];
   my ($active) = $out =~ m{^ \* \s* (.*?) $}mxs;
   return if substr($active, 0, 1) eq '('; # detached head, exact point
   assert_command [qw< git merge >, "origin/$ref"];
   return;
}

1;
__END__
