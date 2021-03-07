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
use Dibs::Run qw< run_command_out run_command_outerr assert_command
   assert_command_out >;

use Exporter 'import';
our @EXPORT_OK = qw<
  cleanup_tags
  docker_commit
  docker_may_rmi
  docker_rm
  docker_rmi
  docker_run
  docker_tag
  docker_version
>;

sub cleanup_tags (@tags) {
   my $cleanup_ok = 1;
   for my $tag (@tags) {
      try { docker_rmi($tag) }
      catch {
         $log->error("failed to remove $tag");
         $cleanup_ok = 0;
      };
   }
   return $cleanup_ok;
} ## end sub cleanup_tags

sub docker_commit ($cid, $tag, $meta = undef) {
   state $change_builder = sub ($name, $data) {
      return uc($name) . ' ' . (ref($data) ? encode_json($data) : $data)
   };
   my @command = qw< docker commit >;
   $meta //= {};
   for my $c (qw< entrypoint cmd label user workdir >) {
      defined(my $cd = $meta->{$c}) or next;
      push @command, -c => $change_builder->($c, $cd)
   }
   for my $change (($meta->{changes} || [])->@*) {
      if (ref($change) eq 'HASH') {
         while (my ($name, $data) = each $change->%*) {
            push @command, -c => $change_builder->($name, $data);
         }
      }
      elsif (! ref($change)) {
         push @command, -c => $change;
      }
      else {
         ouch 400, "invalid change", $change;
      }
   }
   push @command, -a => $meta->{author} if defined $meta->{author};
   push @command, -m => $meta->{message} if defined $meta->{message};
   OUTPUT("committing working container to $tag", INDENT);
   assert_command([@command, $cid, $tag]);
   return $tag;
} ## end sub docker_commit

sub docker_may_rmi ($tag) {
   my ($ecode, $out, $err) = run_command_outerr([qw< docker rmi >, $tag]);
   return if $ecode == 0 || $err =~ m{no \s* such \s* image}imxs;
   ouch 500, "removing tag $tag: $err";
}

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
   push @command, '--cidfile', $cidfile;

   push @command, '--user', $args{user} if exists $args{user};
   push @command, expand_volumes($args{volumes});
   push @command, expand_environment($args{env});
   push @command, '--entrypoint' => '';    # disable, only use CMD below
   push @command, '--workdir' => $args{work_dir} if defined $args{work_dir};
   push @command, $args{image}, $args{command}->@*;

   $log->debug("@command");

   my ($retval, $out) =
     run_command_out(\@command, $args{indent} ? INDENT : 0);
   $log->debug("output<$out>") if defined $out;

   return $retval unless wantarray;

   my $cid;
   if ($cidfile->exists) {
      $cid = $cidfile->slurp_raw;
      $cidfile->remove;
   }
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
