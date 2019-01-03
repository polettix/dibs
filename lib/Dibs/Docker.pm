package Dibs::Docker;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Path::Tiny qw< path >;
use Log::Any qw< $log >;
use Ouch qw< :trytiny_var >;
use JSON::PP qw< encode_json >;
use File::Temp qw< tempfile >;
use Try::Catch;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Dibs::Output;
use Dibs::Run qw< run_command_out assert_command assert_command_out >;

use Exporter 'import';
our @EXPORT_OK = qw<
  docker_commit
  docker_rm
  docker_rmi
  docker_run
  docker_tag
  docker_version
>;

sub docker_commit ($cid, $tag, $changes = undef) {
   my @command = qw< docker commit >;
   $changes //= {};
   for my $c (qw< entrypoint cmd workdir user >) {
      defined(my $cd = $changes->{$c}) or next;
      my $change = uc($c) . ' ' . (ref($cd) ? encode_json($cd) : $cd);
      push @command, -c => $change;
   }
   OUTPUT("committing working container to $tag", INDENT);
   assert_command([@command, $cid, $tag]);
   return $tag;
} ## end sub docker_commit

sub docker_rm ($cid) {
   OUTPUT('removing working container', INDENT);
   assert_command([qw< docker rm >, $cid]);
}

sub docker_rmi ($tag) {
   OUTPUT("removing tag $tag", INDENT);
   assert_command([qw< docker rmi >, $tag]);
   return;
}

sub docker_run (%args) {
   ouch 400, 'no image provided' unless defined $args{image};

   my @command = qw< docker run >;
   my $cidfile = path($args{project_dir})->child("cidfile-$$.tmp");
   $cidfile->remove if $cidfile->exists;
   if (!$args{keep}) {
      push @command, '--rm';
   }
   elsif (wantarray) {
      push @command, '--cidfile', $cidfile;
   }

   push @command, '--user', $args{user} if exists $args{user};
   push @command, expand_volumes($args{volumes});
   push @command, expand_environment($args{env});
   push @command, '--entrypoint' => '';    # disable, only use CMD below
   push @command, '--workdir' => $args{workdir} if defined $args{workdir};
   push @command, $args{image}, $args{command}->@*;

   my ($retval, $out) =
     run_command_out(\@command, $args{indent} ? INDENT : 0);
   return $retval unless wantarray;

   my $cid = $args{keep} && $cidfile->exists ? $cidfile->slurp_raw : undef;
   $cidfile->remove if $cidfile->exists;
   return ($retval, $cid, $out);
} ## end sub docker_run (%args)

sub docker_tag ($src, $dst) {
   OUTPUT("tagging $src as $dst", INDENT);
   assert_command([qw< docker tag >, $src, $dst]);
   return $dst;
}

sub docker_version {
   eval { assert_command_out([qw< docker --version >]) }
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
