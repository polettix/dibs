package Dibs::Role::Identifier;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo::Role;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has id => (is => 'ro', required => 1);
has name => (is => 'ro', lazy => 1, default => sub ($s) { $s->id });

1;
