package Dibs::Role::EnvCarrier;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo::Role;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has "_$_" => (
   is => 'ro',
   default => sub { return [] },
   coerce => sub ($v) { ref($v) eq 'ARRAY' ? $v : [$v] },
   init_arg => $_,
) for qw< env envile >;

sub __as_hash ($name, $first, @objects) {
   unshift @objects, $first if ref $first;
   my $method = "_$name";
   my %retval;
   for my $instance (@objects) {
      for my $item ($instance->$method->@*) {
         my $ref = ref $item;
         if ($ref eq 'HASH') {
            %retval = (%retval, $item->%*);
         }
         elsif ($ref) {
            ouch 400, "invalid item in $name: $ref";
         }
         elsif (exists $ENV{$item}) {
            $retval{$item} = $ENV{$item};
         }
      }
   }
   return \%retval;
}

sub env    ($self) { return __as_hash(env => $self)    }
sub envile ($self) { return __as_hash(envile => $self) }
sub merge_envs     { return __as_hash(env => @_)       }
sub merge_enviles  { return __as_hash(envile => @_)    }

1;
