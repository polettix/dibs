package Dibs::Pack::Factory;
use 5.024;
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< blessed refaddr >;
use Module::Runtime 'use_module';
use Path::Tiny 'path';
use Dibs::Config ':constants';
use Dibs::Inflater ();
use Dibs::Pack::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Factory'; # _config, _inventory, inflate, item, parse

has zone_factory => (is => 'ro', required => 1);

sub instance ($self, $x, %args) {
   my $spec = $self->inflate($x, %args);

   # no circular references so far, protect from creation too
   # FIXME double check this is really needed, although it does
   # not harm really
   my $key = Dibs::Inflater::key_for($x);
   $args{flags}{$key}++;
   my $instance = $self->_create($spec, %args);
   delete $args{flags}{$key};

   return $instance;
}

sub dibspack_factory ($self) { return $self }

sub contains ($s, $x) { return exists $s->_inventory->{key_for($x)} }

sub _create ($self, $spec, %args) {
   my $type = $spec->{type} #self->dwim_type($spec)
     or ouch 400, 'no type present in dibspack';

   # native types lead to static stuff in a zone named after the type
   return $self->_create_static($spec, %args)
     if ($type eq PROJECT) || ($type eq SRC) || ($type eq INSIDE);

   # otherwise it's dynamic stuff to be put in the default zone provided
   return $self->_create_dynamic($spec, %args);
}

sub _create_dynamic ($self, $spec, %args) {
   my $type    = $spec->{type};
   my $fetcher = use_module('Dibs::Fetcher::' . ucfirst $type)->new($spec);
   my $id      = $type . ':' . $fetcher->id;
   my $dyn_zone_name = $args{dynamic_zone} // HOST_DIBSPACKS;
   my $zone    = $self->zone_factory->zone_for($dyn_zone_name);

   return Dibs::Pack::Instance->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      fetcher  => $fetcher,
      location => {base => $id, zone => $zone},
   );
} ## end sub _create_dynamic_dibspack

sub _create_static ($self, $spec, @ignore) {
   my $type = $spec->{type};

   # %location is affected by base (aliased as "raw") and path. Either
   # MUST be present, both is possible
   my %location = (zone => $self->zone_factory->zone_for($type));
   my $fullpath; # useful for assigning an identifier to this dibspack

   if (defined(my $base = $spec->{base} // $spec->{raw} // undef)) {
      $location{base} = $base;
      $fullpath = path($base);
   }

   if (defined(my $path = $spec->{path} // undef)) {
      $location{path} = $path;
      $fullpath = $fullpath ? $fullpath->child($path) : path($path);
   }

   # if $fullpath is not true, none of base(/raw) or path was set
   $fullpath or ouch 400, "invalid base/path for $type dibspack";

   # build %subargs for call to Dibs::Pack::Instance
   my %args = (
      fetcher => undef, # no fetching needed
      id => "$type:$fullpath",
      location => \%location,
   );

   # name presence is optional, rely on default from class if absent
   $args{name} = $spec->{name} if exists $spec->{name};

   return Dibs::Pack::Instance->new(%args);
} ## end sub _create_static_dibspack

sub parse ($self, $spec) {
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
} ## end sub parse ($spec)

1;
