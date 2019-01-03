package Dibs::Role::EnvCarrier;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo::Role;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has "_$_" => (
   is       => 'ro',
   default  => sub { return [] },
   coerce   => sub ($v) { ref($v) eq 'ARRAY' ? $v : [$v] },
   init_arg => $_,
) for qw< env envile >;

sub __as_hash ($aref) {
   my %retval;
   for my $item ($aref->@*) {
      my $ref = ref $item;
      if ($ref eq 'HASH') {
         %retval = (%retval, $item->%*);
      }
      elsif ($ref) {
         my $caller = (caller 1)[3] =~ s{.*::}{}rmxs;
         ouch 400, "invalid item in $caller: $ref";
      }
      elsif (exists $ENV{$item}) {
         $retval{$item} = $ENV{$item};
      }
   } ## end for my $item ($aref->@*)
   return \%retval;
} ## end sub __as_hash ($aref)

sub __merge_hashes ($method, @objects) {
   shift @objects unless @objects && ref $objects[0];
   return {map { $_->$method->%* } reverse @objects};    # first wins!
}

sub env ($self)    { return __as_hash($self->_env) }
sub envile ($self) { return __as_hash($self->_envile) }
sub merge_envs     { return __merge_hashes(env => @_) }
sub merge_enviles  { return __merge_hashes(envile => @_) }

sub append_env ($self, @s) { push $self->_env->@*, @s }
sub append_envile ($self, @s) { push $self->_envile->@*, @s }

1;
