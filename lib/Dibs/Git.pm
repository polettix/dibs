package Dibs::Git;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use IPC::Run ();
use File::chdir;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
no warnings qw< experimental::postderef experimental::signatures >;

sub fetch ($uri, $path) {
   my $ref = $uri =~ m{\#}mxs ? $uri =~ s{\A.*\#}{}rmxs : 'master';
   _fetch($uri =~ s{\#.*}{}rmxs, $path);
   _checkout_ref($path, $ref);
}

sub _fetch ($origin, $dir) {
   $dir = path($dir);
   return _clone($origin, $dir) unless $dir->child('.git')->exists;

   my $current_origin = _current_origin($dir);
   if ($current_origin ne $origin) {
      $log->info("changed origin, re-cloning");
      $dir->remove_tree({safe => 0});
      return _clone($origin, $dir);
   }

   local $CWD = $dir->stringify;
   IPC::Run::run [qw< git fetch origin >]
      or ouch 500, 'cannot fetch from origin';

   return $dir;
}

sub _clone ($origin, $dir) {
   $dir = path($dir)->stringify;
   IPC::Run::run [qw< git clone >, $origin, $dir]
      or ouch 500, "cannot clone '$origin' into '$dir'";
   return;
}

sub _current_origin ($path) {
   local $CWD = path($path)->stringify;
   IPC::Run::run [qw< git remote get-url origin >], \undef, \my $out
      or ouch 500, "cannot find origin's URL";
   return $out =~ s{\s+\z}{}rmxs;
}

sub _checkout_ref ($path, $ref = 'master') {
   local $CWD = path($path)->stringify;
   IPC::Run::run [qw< git checkout >, $ref]
      or ouch 500, "cannot checkout ref '$ref'";
   IPC::Run::run [qw< git branch >], \undef, \my $out
      or ouch 500, 'cannot get list of branches';
   my ($active) = $out =~ m{^ \* \s* (.*?) $}mxs;
   return if substr($active, 0, 1) eq '('; # detached head, exact point
   IPC::Run::run [qw< git merge >, "origin/$ref"]
      or ouch 500, "cannot merge from 'origin/$ref'";
   return;
}

1;
__END__
