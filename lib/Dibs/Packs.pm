package Dibs::Packs;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Scalar::Util qw< blessed refaddr >;
use Dibs::Pack;
use Dibs::Config ':constants';
use Dibs::Inflater qw< inflate key_for >;
use Module::Runtime 'use_module';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _config    => (
   is => 'ro',
   init_arg => 'config',
   default => sub { return {} },
);
has _inventory => (is => 'ro', default => sub { return {} });
has zone_factory => (is => 'ro', required => 1);

sub item ($self, $x, %opts) {
   return Dibs::Pack->new( # "promise" to do something when needed
      factory => sub {
         my $key = key_for($x);
         my $inv = $self->_inventory;
         my $instance = $inv->{$key} //= do {
            my $cfg = $self->_config;
            my $spec = $cfg->{spec} = inflate(
               %opts,
               config    => $cfg,
               dibspacks => $self,
               parser    => sub ($v) { $self->_normalize($v) },
               spec      => $x,
               type      => 'dibspack',
            );

            # no circular references so far, protect from creation too
            # FIXME double check this is really needed, although it does
            # not harm really
            $opts{flags}{$key}++;
            my $instance = $self->_create($spec, %opts);
            delete $opts{flags}{$key};

            my $id_key = key_for($instance);
            $inv->{$id_key} //= $instance;
            $instance;
         };
      },
   );
}

sub contains ($s, $x) { return exists $s->_inventory->{key_for($x)} }

sub _create ($self, $spec, %opts) {
   my $type = $spec->{type} or ouch 400, 'no type present in dibspack';

   # native types lead to static stuff in a zone named after the type
   return $self->_create_static($spec, %opts)
     if ($type eq PROJECT) || ($type eq SRC) || ($type eq INSIDE);

   # otherwise it's dynamic stuff to be put in the default zone provided
   return $self->_create_dynamic($spec, %opts);
}

sub _create_dynamic ($self, $spec, %opts) {
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

sub _create_static ($self, $spec, %opts) {
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

1;
