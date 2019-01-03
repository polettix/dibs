package Dibs::Stroke;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'env',               #
   'envile',            #
   'id',                #
   'container_path',    #
   'name',              #
   'draw',              #
);

1;
