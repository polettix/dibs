package Dibs::Process::Instance;
use 5.024;
use Ouch qw< :trytiny_var >;
use Log::Any '$log';
use Scalar::Util qw< refaddr >;
use Try::Catch;
use Dibs::Inflater 'flatten_array';
use Dibs::Docker qw< docker_commit docker_rm docker_rmi docker_tag >;
use Dibs::Output;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::EnvCarrier';
with 'Dibs::Role::Identifier';

has action_factory => (is => 'ro', required => 1);
has dibspack_factory => (
   is      => 'ro',
   lazy    => 1,
   default => sub ($self) { $self->action_factory->dibspack_factory },
);

has all_actions => (is => 'lazy');
has actions => (is => 'ro', default  => sub { return [] });
has commit  => (is => 'ro', default  => undef, coerce => \&_coerce_commit);
has from    => (is => 'ro', required => 1);

sub _build_all_actions ($self) {
   my $af = $self->action_factory;
   return [ map { $af->item($_) } flatten_array($self->actions) ];
}

sub changes_for_commit ($self) {
   my $cfg = $self->commit;
   my %changes = (
      cmd        => [],
      entrypoint => [qw< /bin/sh -l >],
   );
   for my $key (qw< entrypoint cmd workdir user >) {
      $changes{$key} = $cfg->{$key} if defined $cfg->{$key};
   }
   return \%changes;
} ## end sub changes_for_commit

sub cleanup_tags ($self, @tags) {
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

sub _coerce_commit ($cfg) {
   return {keep => 0} unless defined $cfg;

   my $ref = ref $cfg;
   return {keep => 1, $cfg->%*} if $ref eq 'HASH';
   return {keep => 1, tags => $cfg} if $ref eq 'ARRAY';

   # the "false" one is probably overkill here
   return {keep => 0}
     if $cfg =~ m{\A(?:n|N|no|No|NO|false|False|FALSE|off|Off|OFF)\z}mxs;
   return {keep => 1, tags => [':default:']}
     if $cfg =~ m{\A(?:y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON)\z}mxs;

   ouch 400, "unhandled ref type $ref for commit field" if $ref;
   return {keep => 1, tags => [$cfg]};
}

sub finalize ($self, $image) {
   my $commit = $self->commit;
   return $self->remove_working($image) unless $commit->{keep};

   ARROW_OUTPUT('+', 'commit required');
   my $remove_working = 1;
   my @tags = $image;
   try {
      my $name = $self->name;
      my %done = ($image => 1);
      for my $tag (($commit->{tags} // [])->@*) {
         if (($tag eq '*') || ($tag eq ':default:')) {
            $remove_working = 0;
         }
         else {
            my $dst = $tag =~ m{:}mxs ? $tag : "$name:$tag";
            next if $done{$dst}++;
            docker_tag($image, $dst);
            push @tags, $dst;
         } ## end else [ if (($tag eq '*') || (...))]
      }
      # cleanup if necessary
      $self->remove_working(shift @tags) if $remove_working && @tags > 1;
   }
   catch {
      $self->cleanup_tags(@tags);
      die $_; # rethrow exception
   };

   return \@tags;
}

sub image ($self, $to) {
   my $from = $self->from;
   return try { docker_tag($from, $to) }
   catch { ouch 400, "Cannot tag $from to $to. Build $from maybe?" };
}

sub remove_working ($self, $image) {
   ARROW_OUTPUT('+', 'removing working image, not needed');
   $self->cleanup_tags($image)
      or ouch 500, 'dirty condition, will not proceed';
   return;
}

sub run ($self, %args) {
   ARROW_OUTPUT('=', 'process ' . $self->name);
   $args{process} = $self;    # self-explanatory...
   $args{env_carriers} = [ $self, ($args{env_carriers} // [])->@* ];

   # "clone" image so that we will work on it over and over
   my $image = $self->image($args{working_image_name});

   my %retval;
   try {
      $retval{outputs} = $self->run_actions(%args, image => $image);
   }
   catch {
      docker_rmi($image);     # roll back $image
      die $_;                 # rethrow exception
   };

   # this will get rid of $image properly, even on exceptions, unless
   # $image itself has to be kept
   my $tags = $self->finalize($image);
   $retval{tags} = $tags if defined $tags;

   return \%retval;
} ## end sub run

sub run_actions ($self, %args) {
   my $cid;    # records the container id, useful for catch-cleanup
   my @outputs;
   try {
      my @actions = $self->all_actions->@*;
      my $index = 0;
      my $changes = undef;
      @outputs = map {
         my ($ecode, $out);
         ($ecode, $cid, $out) = $_->run(%args);
         ouch 500, "action failed (exit code $ecode)" if $ecode;

         $changes = $self->changes_for_commit
            if $index++ == $#actions; # last action gets changes too
         docker_commit($cid, $args{image}, $changes);

         # avoid calling docker_rm twice in case of errors
         (my $__cid, $cid) = ($cid, undef);
         docker_rm($__cid);

         # this is the "output" of this map pass
         $out;
      } @actions;
   } ## end try
   catch {
      docker_rm($cid) if defined $cid;
      die $_;    # rethrow
   };
   return \@outputs;
} ## end sub run_actions

1;
