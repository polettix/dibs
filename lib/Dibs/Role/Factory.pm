package Dibs::Role::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Module::Runtime ();
use Scalar::Util qw< blessed refaddr weaken >;
use Log::Any '$log';
use Moo::Role;
use Guard;
use Module::Runtime 'use_module';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

requires qw< _build__class_for normalize pack_factory >;

has ancestors => (is => 'ro', default => sub { return [] });

has _cache => (
   is => 'ro',
   init_arg => 'cache',
   default => sub { return {} },
);

has _class_for => (
   is => 'lazy',
   init_arg => undef,
);

has _config => (
   is => 'ro',
   init_arg => 'config',
   default => sub { return {} },
);

has _inventory => (is => 'ro', default => sub { return {} });

sub key_for($self, $x) {
   return blessed $x ? 'id:' . $x->id
      : ref $x       ? 'refaddr:' . refaddr($x)
      : defined $x   ? 'string:' . $x
      :                ouch 400, 'invalid undefined element for key';
}

sub _no_circular_reference ($self, $spec, $flags) {
   my $key  = $self->key_for($spec);
   if ($log->is_trace) {
      my $list = join ', ', keys $flags->%*;
      $log->trace("inflate, key<$key> against flags{$list}");
   }
   my $type = $self->type;
   ouch 400, "circular reference resolving $type $key" if $flags->{$key};
   $flags->{$key}++;
   return ($key, guard { delete $flags->{$key} });
}

sub _extensions ($self, $spec, %args) {
   return $self->inflate($spec, %args) unless ref $spec eq 'ARRAY';

   my ($k, $g) = $self->_no_circular_reference($spec, $args{flags});
   my $c = $self->_cache->{extensions} //= {};
   my $r = $c->{$k} //= [map { $self->_extensions($_, %args) } $spec->@*];
   return $r->@*;
}

sub inflate ($self, $x, %args) {
   my $type = $self->type;
   defined $x or ouch 400, "undefined specification for $type";

   my ($k, $g) = $self->_no_circular_reference($x, $args{flags} //= {});
   my $cache = $self->_cache->{stuff} //= {};
   return $cache->{$k} if exists $cache->{$k};

   my $spec = $self->pre_inflate($x, %args);
   my ($ref, $rv) = (ref $spec, undef);
   if ($ref eq '') { # scalar, treat as string
      if (my ($name, $pack) = $spec =~ m{\A (.*?) \@ (.*) \z}mxs) {
         ouch 500, 'TRANSFER IMPLEMENTATION FROM INFLATER HERE!';
         $rv = $self->load_from_pack($name, $spec, %args);
      }
      else {
         my $config = $self->_config;
         ouch 400, "unknown $type $spec" unless exists $config->{$spec};
         $rv = $self->inflate($config->{$spec}, %args);
      }
   }
   elsif ($ref eq 'HASH') {
      $rv = { $spec->%* };
      if (exists $rv->{extends}) {
         my @extensions = $self->_extensions($rv, %args);
         $rv->%* = ((map { $_->%* } reverse @extensions), $rv->%*);
      }
   }
   else { ouch 500, 'something still not implemented here?'; }

   # save in breadcrumbs. Not sure weaken is really necessary here, but
   # whatever... something might become undef eventually
   my @crumb = ($x, $spec);
   weaken($crumb[$_]) for 0 .. $#crumb;
   my $breadcrumbs = $rv->{breadcrumbs} //= [];
   unshift $breadcrumbs->@*, \@crumb;

   return $cache->{$k} = $rv;
}

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);
   $spec = $self->normalize($spec, %args);
   my $class = $self->class_for($spec, %args);
   return $class->create(%args, spec => $spec, factory => $self);
}

sub class_for ($self, $spec, %args) {
   my $type = $spec->{type};
   my $class = $type =~ m{::}mxs ? $type : $self->_class_for->{$type};
   return use_module($class);
}

sub item ($self, $x, %args) {
   return $self->proxy_class->new( # "promise" to do something when needed
      factory => sub {
         my $inventory = $self->_inventory;
         $inventory->{$self->key_for($x)} //= do {
            my $instance = $self->instance($x, %args);
            $inventory->{$self->key_for($instance)} //= $instance;
         };
      },
   );
}

# a default that passes hashes through and calls parse when needed
sub pre_inflate ($self, $x, %args) {
   my $ref = ref $x;
   return $x if $ref eq 'HASH';
   ouch 400, "invalid input for instance ($ref -> $x)" if $ref ne '';

   if (my ($type, $raw) = $x =~ m{\A (\w+ (::\w+)*) : (.*) \z}mxs) {
      my $class = $self->class_for({type => $type}, %args);
      my $retval = $class->parse($type, $raw);
      $retval->{type} //= $type;
      return $retval;
   }

   # last resort, it might be a reference to something else
   return $x;
}

sub proxy_class ($self) {
   my $package = ref($self) || $self;
   return Module::Runtime::use_module($package =~ s{::Factory}{}rmxs);
}

sub type ($self) {
   my $package = ref($self) || $self;
   my ($type) = $package =~ m{\A Dibs:: (.*) ::Factory \z}mxs;
   return $type;
}

1;
__END__

sub inflateXXXx ($self, $x, %args) {
   return Dibs::Inflater::inflate(
      $x,
      %args,
      config       => $self->_config,
      pack_factory => $self->pack_factory,
      normalizer   => sub ($v) { $self->normalize($v) },
      parser       => sub ($v) { $self->parse($v) },
      type         => $self->type,
   );
}

