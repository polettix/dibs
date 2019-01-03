package Dibs::Proxy;
use 5.024;
use Ouch ':trytiny_var';
use Module::Runtime qw< use_module >;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has factory => (
   is       => 'ro',
   required => 1,
   isa      => sub { ouch 400, 'factory MUST be a factory method' }
);
has instance => (is => 'lazy');

sub _build_instance ($self) { $self->factory->() }

sub create ($package, $factory_class, $cache, $config) {
   use_module($factory_class)->create($cache, $config);
}

sub creator ($package, $factory, $cache) {
   return sub ($config) { $package->create($factory, $cache, $config) };
}

1;
