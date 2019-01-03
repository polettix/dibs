package Dibs::Process;
use 5.024;
use Moo;

with 'Dibs::Role::Proxy';

__PACKAGE__->_proxy_methods(
   'env',       #
   'envile',    #
   'id',        #
   'name',      #
   'run',       #
);

1;
