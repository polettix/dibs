package Dibs::Action;
use 5.024;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'execute', #
   'id',   #
   'name', #
   'output_marked', #
   'output', #
);

sub create ($class, $target, $factory, %args) {
   $class->new(factory => sub { $factory->instance($target, %args) })
}

1;
