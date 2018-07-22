package Dibs::Docker;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use IPC::Run ();
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use JSON::PP qw< encode_json >;
use File::Temp qw< tempfile >;
no warnings qw< experimental::postderef experimental::signatures >;

sub _assert_command (@command) {
   my ($out);
   $log->debug("$$ _assert_command(@command)");
   for my $i (0 .. $#command) {
      my $v = defined($command[$i]) ? $command[$i] : '*undef*';
      $log->debug("command[$i] = $v");
   }
   IPC::Run::run \@command, \undef, \$out, \*STDERR
      or ouch 500, "failed command (@command)";
   $log->debug("executed (@command), got $out");
   return ($out);
}

sub docker_tag ($src, $dst) {
   _assert_command(qw< docker tag >, $src, $dst);
   return $dst;
}

sub docker_rmi ($tag) {
   _assert_command(qw< docker rmi >, $tag);
   return;
}

sub docker_rm ($cid) {
   _assert_command(qw< docker rm >, $cid);
}

sub docker_commit ($cid, $tag, $changes = undef) {
   my @command = qw< docker commit >;
   $changes //= {};
   for my $c (qw< entrypoint cmd >) {
      defined (my $cd = $changes->{$c}) or next;
      my $change = uc($c) . ' ' . (ref($cd) ? encode_json($cd) : $cd);
      push @command, -c => $change;
   }
   _assert_command(@command, $cid, $tag);
   return $tag;
}

sub docker_run (%args) {
   my @command = qw< docker run >;
   my $cidfile = path($args{project_dir})->child("cidfile-$$.tmp");
   $cidfile->remove if $cidfile->exists;
   if (! $args{keep}) {
      push @command, '--rm';
   }
   elsif (wantarray) {
      push @command, '--cidfile', $cidfile;
   }

   push @command, expand_volumes($args{volumes});
   push @command, expand_environment($args{env});
   my ($entrypoint, @ep_args) = $args{command}->@*;
   push @command, '--entrypoint' => $entrypoint;

   ouch 400, "no image provided in $entrypoint"
      unless defined $args{image};
   push @command, $args{image};

   push @command, @ep_args;

   $log->debug("running: @command");
   my ($out);
   IPC::Run::run \@command, \undef, \$out, \*STDERR;

   return $? unless wantarray;

   my $cid = $args{keep} ? $cidfile->slurp_raw : undef;
   $cidfile->remove if $cidfile->exists;
   return ($?, $cid, $out);
}

sub expand_environment ($env) {
   map { -e => "$_=$env->{$_}" } keys $env->%*;
}

sub expand_volumes ($vols) {
   map { -v => $_ }
      map { ref($_) ? join(':', $_->@*) : $_ } $vols->@*;
}

1;
__END__
