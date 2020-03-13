package Dibs::Pack::Static::Project;
use 5.024;
use Dibs::Config ':constants';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

extends 'Dibs::Pack::Static';

around create => sub ($orig, $self, %args) {
   return $self->$orig(%args, zone_name => PACK_STATIC);
};

1;
__END__
