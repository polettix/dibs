package Dibs::Packs;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Scalar::Util qw< blessed refaddr >;
use Dibs::Pack;
use Dibs::Config ':constants';
use Module::Runtime 'use_module';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _inventory => (is => 'ro', default => sub { return {} });
has zone_factory => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %specs = (@args && ref($args[0])) ? $args[0]->%* : @args;
   $specs{_inventory} = \my %inventory;
   if (exists $specs{inventory}) {
      my $hash = delete $specs{inventory};
      while (my ($name, $value) = each $hash->%*) {
         my $key = $class->_key_for($name);
         $inventory{$key}{spec} = $value;
      }
   }
   return \%specs;
}

sub _key_for($self, $x) {
   return blessed $x ? 'id:' . $x->id
      : ref $x       ? 'refaddr:' . refaddr($x)
      : defined $x   ? 'string:' . $x
      :                ouch 400, 'invalid undefined element for key';
}

sub item ($self, $x, %opts) {
   return Dibs::Pack->new( # "promise" to do something when needed
      factory => sub {
         my $key = $self->_key_for($x);
         my $inv = $self->_inventory;
         my $slot = $inv->{$key} //= {spec => $x};
         my $instance = $slot->{instance} //= do {
            ouch "circular reference for dibspack '$key'"
              if $opts{flags}{$key}++;

            my $spec = $slot->{spec} = 
              $self->_expand($self->_normalize($slot->{spec}), %opts);
            my $instance = $self->_inflate($spec, %opts);

            delete $opts{flags}{$key};

            my $id_key = $self->_key_for($instance);
            $inv->{$id_key}{instance} //= $instance;
            $instance;
         };
      },
   );
}

sub contains ($self, $x) {
   my $key = $self->_key_for($x);
   return exists $self->_inventory->{$key};
}

sub _inflate ($self, $spec, %opts) {
   my $type = $spec->{type} or ouch 400, 'no type present in dibspack';

   # native types lead to static stuff in a zone named after the type
   return $self->_inflate_static($spec, %opts)
     if ($type eq PROJECT) || ($type eq SRC) || ($type eq INSIDE);

   # otherwise it's dynamic stuff to be put in the default zone provided
   return $self->_inflate_dynamic($spec, %opts);
}

sub _inflate_dynamic ($self, $spec, %opts) {
   my $type    = $spec->{type};
   my $fetcher = use_module('Dibs::Fetcher::' . ucfirst $type)->new($spec);
   my $id      = $type . ':' . $fetcher->id;
   my $dyn_zone_name = $opts{dynamic_zone} // HOST_DIBSPACKS;
   my $zone    = $self->zone_factory->zone_for($dyn_zone_name);

   return use_module('Dibs::Pack::Dynamic')->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      cloner   => $opts{cloner},
      fetcher  => $fetcher,
      location => {path => $id, zone => $zone},
   );
} ## end sub _create_dynamic_dibspack

sub _inflate_static ($self, $spec, %opts) {
   my $type = $spec->{type};
   defined(my $path = $spec->{path} // $spec->{raw})
     or ouch 400, "invalid path for $type dibspack";

   # build @args for call to Dibs::Pack::Static's constructor
   my $zone = $self->zone_factory->zone_for($type);
   my @args = (
      id       => "$type:$path",
      location => {path => $path, zone => $zone},
   );

   # name presence is optional, rely on default from class if absent
   push @args, name => $spec->{name} if exists $spec->{name};

   return use_module('Dibs::Pack::Static')->new(@args);
} ## end sub _create_static_dibspack

sub _normalize ($self, $spec) {
   if (!ref($spec)) {
      my %hash;
      if ($spec =~ m{\A git://}mxs) {
         $hash{type}   = GIT;
         $hash{origin} = $spec;
      }
      elsif ($spec =~ m{\A https?://}mxs) {
         $hash{type} = HTTP;
         $hash{URI}  = $spec;
      }
      elsif (my ($type, $raw) = $spec =~ m{\A ([^:]+) : (.*) \z}mxs) {
         $hash{type} = $type;
         $hash{raw}  = $raw;
      }
      else {
         ouch 400, "cannot parse dibspack specification '$spec'";
      }

      $spec = \%hash;
   } ## end if (!ref($spec))

   ouch 400, 'invalid input specification for dibspack'
     unless ref($spec) eq 'HASH';

   # DWIM-my stuff here
   $spec->{type} = IMMEDIATE
     if (!exists($spec->{type})) && exists($spec->{run});

   $spec->{type} = lc $spec->{type} if exists $spec->{type};
   return $spec;
} ## end sub _normalize ($spec)

sub _expand ($self, $spec, %opts) {
   my $key = $self->_key_for($spec);
   ouch 400, "circular reference resolving $key" if $opts{flags}{$key}++;

   my $rv;
   my $ref = ref $spec;
   if (! $ref) {
      my $inv = $self->_inventory;
      ouch "unknown dibspack $spec" unless exists $inv->{$key};
      $rv = $self->_expand($self->_normalize($inv->{$key}{spec}), %opts);
   }
   elsif ($ref eq 'ARRAY') {
      $rv = { map { $self->_expand($_, %opts)->%* } reverse $spec->@* };
   }
   elsif ($ref eq 'HASH') {
      if (exists $spec->{extends}) {
         my $expansions = $self->_expand(delete($spec->{extends}), %opts);
         $spec->%* = ($expansions->%*, $spec->%*);
      }
      $rv = $spec;
   }
   else {
      ouch 500, 'something still not implemented here?';
   }
   
   # free this up for avoiding circular references
   delete $opts{flags}{$key};

   return $rv;
}

1;
