package Dibs::Role::Factory;
use 5.024;
use Dibs::Inflater qw< key_for >;
use Module::Runtime qw< use_module >;
use Moo::Role;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

requires qw< dibspack_factory instance parse >;

has _config => (
   is => 'ro',
   init_arg => 'config',
   default => sub { return {} },
);

has _inventory => (is => 'ro', default => sub { return {} });

sub inflate ($self, $x, %args) {
   return Dibs::Inflater::inflate(
      $x,
      %args,
      config           => $self->_config,
      dibspack_factory => $self->dibspack_factory,
      parser           => sub ($v) { $self->parse($v) },
      type             => $self->type,
   );
}

sub item ($self, $x, %args) {
   return $self->proxy_class->new( # "promise" to do something when needed
      factory => sub {
         my $inventory = $self->_inventory;
         $inventory->{key_for($x)} //= do {
            my $instance = $self->instance($x, %args);
            $inventory->{key_for($instance)} //= $instance;
            $instance;
         };
      },
   );
}

sub proxy_class ($self) {
   my $package = ref($self) || $self;
   return use_module($package =~ s{::Factory}{}rmxs);
}

sub type ($self) {
   my $package = ref($self) || $self;
   my ($type) = $package =~ m{\A Dibs:: (.*) ::Factory \z}mxs;
   return $type;
}

1;
