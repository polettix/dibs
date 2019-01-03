package Dibs::Pack;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'container_path',    #
   'host_path',         #
   'id',                #
   'materialize',       #
   'name',              #
   'location',          #
);

1;
