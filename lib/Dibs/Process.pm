package Dibs::Process;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Scalar::Util qw< refaddr >;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::EnvCarrier';

has actions => (is => 'ro', default => sub { return [] });
has commit => (is => 'ro', default => undef);
has from => (is => 'ro', required => 1);

1;
