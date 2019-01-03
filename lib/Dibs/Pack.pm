package Dibs::Pack;
use 5.024;
use experimental qw< postderef signatures >;
use Ouch qw< :trytiny_var >;
use Module::Runtime qw< use_module >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config qw< :constants >;
use Dibs::Pack::Dynamic;

sub create_dibspack ($spec, %opts) {
   $spec = _normalize($spec);
   my $type = $spec->{type} or ouch 400, 'no type present in dibspack';

   # native types lead to static stuff in a zone named after the type
   return _create_static_dibspack($spec, %opts)
     if ($type eq PROJECT) || ($type eq SRC) || ($type eq INSIDE);

   # otherwise it's dynamic stuff to be put in the default zone provided
   return _create_dynamic_dibspack($spec, %opts);
} ## end sub create_dibspack

sub _create_dynamic_dibspack ($spec, %opts) {
   my $type    = $spec->{type};
   my $fetcher = use_module('Dibs::Fetcher::' . ucfirst $type)->new($spec);
   my $id      = $type . ':' . $fetcher->id;
   my $zone    = $opts{zone_factory}->zone_for($opts{dynamic_zone});

   require Dibs::Pack::Dynamic;
   return Dibs::Pack::Dynamic->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      cloner   => $opts{cloner},
      fetcher  => $fetcher,
      location => {path => $id, zone => $zone},
   );
} ## end sub _create_dynamic_dibspack

sub _create_static_dibspack ($spec, %opts) {
   my $type = $spec->{type};
   defined(my $path = $spec->{path} // $spec->{raw})
     or ouch 400, "invalid path for $type dibspack";

   # build @args for call to Dibs::Pack::Static's constructor
   my $zone = $opts{zone_factory}->zone_for($type);
   my @args = (
      id       => "$type:$path",
      location => {path => $path, zone => $zone},
   );

   # name presence is optional, rely on default from class if absent
   push @args, name => $spec->{name} if exists $spec->{name};

   require Dibs::Pack::Static;
   return Dibs::Pack::Static->new(@args);
} ## end sub _create_static_dibspack

sub _normalize ($spec) {
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
