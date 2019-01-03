package Dibs::Action::Frame;
use 5.024;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

sub create ($class, %args) {

}

sub draw ($self, $args = undef) {
   ouch 400, 'snap: no arguments, wrong place?' unless defined $args;

   ...;


   return $args;
}

1,
__END__
