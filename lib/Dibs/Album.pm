package Dibs::Album;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'env',       #
   'envile',    #
   'id',        #
   'name',      #
   'draw',      #
   'sketches',  #
);

1;
