package Dibs::Role::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Module::Runtime ();
use Scalar::Util qw< blessed refaddr weaken >;
use Log::Any '$log';
use Moo::Role;
use Guard;
use Module::Runtime 'use_module';
use YAML::XS 'LoadFile';
use Dibs::Config ':constants';
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
      if (my ($name, $packpath) = $spec =~ m{\A (.*?) \@ (.*) \z}mxs) {
         $rv = $self->load_from_pack($packpath, $name, %args);
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
         my @extensions = $self->_extensions($rv->{extends}, %args);
         $rv->%* = ((map { $_->%* } reverse @extensions), $rv->%*);
      }
   }
   else { ouch 500, 'something still not implemented here?'; }

   # FIXME this whole breadcrumbs story is basically broken
   # save in breadcrumbs. Not sure weaken is really necessary here, but
   # whatever... something might become undef eventually
   my @crumb = ($x, $spec);
   ref($crumb[$_]) && weaken($crumb[$_]) for 0 .. $#crumb;
   my $breadcrumbs = $rv->{breadcrumbs} //= [];
   unshift $breadcrumbs->@*, \@crumb;

   return $cache->{$k} = $rv;
}

sub instance ($self, $x, %args) {
   my $flags = $args{flags} //= {};
   my $spec = $self->inflate($x, %args);
   my ($key, $guard) = $self->_no_circular_reference($x, $flags);
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

   if (my ($type, $raw) = $x =~ m{\A (\w+ (?: ::\w+)*) : (.*) \z}mxs) {
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

sub load_from_pack ($self, $packpath, $name, %args) {
   my %spec = (factory_type => $self->type);
   @spec{qw< pack path >} = split m{/}mxs, $packpath, 2;
   my $sub_factory = $self->pack_factory->get_sub_factory(\%spec, %args);
   return $sub_factory->inflate($name, %args);
}

sub Yload_from_pack ($self, $packpath, $name, %args) {
   my ($packname, @path) = split m{/}mxs, $packpath, 2;
   my $pack = $self->pack_factory->item($packname,
      dynamic_zone => PACK_HOST_ONLY, %args);
   my $dibsfile = $pack->host_path(@path);
   my $subdibs = $args{dibs}->subordinate(LoadFile($dibsfile));
}

sub Xload_from_pack ($spec, %as) {
   my $p = resolve_pack($spec, dynamic_zone => PACK_HOST_ONLY, %as);
   my @path = defined($p->{path}) ? $p->{path} : ();
   my $path = $p->{pack}->location->host_path(@path);
   ouch 404, "missing file $path" unless $path->exists;
   my $whole = LoadFile($path);

   # ensure the needed data are there
   my $data = data_in($whole, $p->{datapath});

   my $zf = $as{zone_factory} // $as{pack_factory}->zone_factory;
   my $cf = $whole->{&PACKS} // {};
   require Dibs::Pack::Factory;
   my $ldps = Dibs::Pack::Factory->new(config => $cf, zone_factory => $zf);
   return inflate($data, %as, dispack_factory => $ldps, config => $cf);
}

1;
__END__
