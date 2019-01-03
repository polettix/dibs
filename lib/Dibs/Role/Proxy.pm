package Dibs::Role::Proxy;
use 5.024;
use Ouch ':trytiny_var';
use Moo::Role;
use experimental 'signatures';
no warnings 'experimental::signatures';

has _factory => (
   is       => 'ro',
   required => 1,
   init_arg => 'factory',
   isa      => sub {
      ouch 400, 'factory MUST be a factory method'
        unless ref($_[0]) eq 'CODE';
   },
);

has _instance => (is => 'lazy');

sub _build__instance { $_[0]->_factory->() }

sub _proxy_methods ($package, @names) {
   for my $name (@names) {
      my $method = sub ($self, @args) { $self->_instance->$name(@args) };
      no strict 'refs';
      *{$package . '::' . $name} = $method;
   }
}

1;
