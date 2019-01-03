package Dibs::Action;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'id',   #
   'name', #
   'draw', #
);

1;
