package Dibs::Pack::Factory;
use 5.024;
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< blessed refaddr >;
use Log::Any '$log';
use Module::Runtime 'use_module';
use Path::Tiny 'path';
use Dibs::Config ':constants';
use Dibs::Pack::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Factory';

has zone_factory => (is => 'ro', required => 1);

sub _build__class_for ($self) {
   return {
      &GIT       => 'Dibs::Pack::Dynamic',
      &IMMEDIATE => 'Dibs::Pack::Dynamic',
      &INSIDE    => 'Dibs::Pack::Static',
      &PROJECT   => 'Dibs::Pack::Static::Project',
      &SRC       => 'Dibs::Pack::Static',
   };
}

sub pack_factory ($self) { return $self }

sub normalize ($self, $spec, %args) {
   # DWIM-my stuff here
   if (! defined $spec->{type}) {
      $log->debug("no explicit type set");
      my $m;
      if (($m) = grep { exists $spec->{$_} } qw< run program >) {
         $spec->{type} = IMMEDIATE;
         $spec->{program} = delete $spec->{$m} if $m ne 'program';
      }
      elsif (($m) = grep { exists $spec->{$_} } SRC, INSIDE, PROJECT) {
         $spec->{type} = $m;
         $spec->{base} = delete $spec->{$m};
      }
      elsif (($m) = grep { exists $spec->{$_} } GIT, 'origin') {
         $spec->{type} = GIT;
         $spec->{origin} = delete $spec->{$m} if $m ne 'origin';
      }
   }

   my $ptype = $spec->{type} // '(still none defined)';
   $log->debug("normalized type: $ptype");

   return $spec;
}

around pre_inflate => sub ($orig, $self, $x, %args) {
   return $self->$orig($x, %args) if ref $x;
   return {type => GIT,  origin => $x} if $x =~ m{\A git://    }mxs;
   return {type => HTTP, URI => $x}    if $x =~ m{\A https?:// }mxs;
   return $self->$orig($x, %args); # turn to regular munging
};

1;
__END__

sub _old_create_dynamic ($self, $spec, %args) {
   my $type    = $spec->{type};
   my $fetcher = use_module('Dibs::Fetcher::' . ucfirst $type)->new($spec);
   my $id      = $type . '/' . $fetcher->id;
   my $dyn_zone_name = $args{dynamic_zone} // PACK_HOST_ONLY; # FIXME
   my $zone    = $self->zone_factory->zone_for($dyn_zone_name);

   return Dibs::Pack::Instance->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      fetcher  => $fetcher,
      location => {base => $id, zone => $zone},
   );
} ## end sub _create_dynamic_pack

sub _old_create_static ($self, $spec, @ignore) {
   my $type = $spec->{type};

   # %location is affected by base (aliased as "raw") and path. Either
   # MUST be present, both is possible
   state $zone_name_for = { &PROJECT => PACK_STATIC };
   my $zone_name = $zone_name_for->{$type} //= $type;
   my %location = (zone => $self->zone_factory->zone_for($zone_name));
   my $fullpath; # useful for assigning an identifier to this pack

   if (defined(my $base = $spec->{base} // $spec->{raw} // undef)) {
      $location{base} = $base;
      $fullpath = path($base);
   }

   if (defined(my $path = $spec->{path} // undef)) {
      $location{path} = $path;
      $fullpath = $fullpath ? $fullpath->child($path) : path($path);
   }

   # if $fullpath is not true, none of base(/raw) or path was set
   $fullpath or ouch 400, "invalid base/path for $type pack";

   # build %subargs for call to Dibs::Pack::Instance
   my %args = (
      fetcher => undef, # no fetching needed
      id => "$type:$fullpath",
      location => \%location,
   );

   # name presence is optional, rely on default from class if absent
   $args{name} = $spec->{name} if exists $spec->{name};

   return Dibs::Pack::Instance->new(%args);
} ## end sub _create_static_pack

sub _create ($self, $spec, %args) {
   my $type = $spec->{type} #self->dwim_type($spec)
     or ouch 400, 'no type present in pack';

   $log->debug("factory: creating pack of type $type");

   # native types lead to static stuff in a zone named after the type
   return $self->_create_static($spec, %args)
     if ($type eq PROJECT) || ($type eq SRC) || ($type eq INSIDE);

   # otherwise it's dynamic stuff to be put in the default zone provided
   return $self->_create_dynamic($spec, %args);
}

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
