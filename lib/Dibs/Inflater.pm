package Dibs::Inflater;
use 5.024;
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< refaddr blessed >;
use Log::Any '$log';
use Moo;
use Dibs::Config ':constants';
use Dibs::Pack::Factory;
use YAML::XS qw< LoadFile >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

use Exporter 'import';
our @EXPORT_OK = qw<
   flatten_array
   inflate key_for
   resolve_buildpack
   load_from_buildpack
>;
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

sub key_for($x) {
   return blessed $x ? 'id:' . $x->id
      : ref $x       ? 'refaddr:' . refaddr($x)
      : defined $x   ? 'string:' . $x
      :                ouch 400, 'invalid undefined element for key';
}

sub inflate ($spec, %args) {
   defined $spec or ouch 400, "undefined specification for $args{type}";

   # check circular dependencies, complain if present
   my $key  = key_for($spec);
   ouch 400, "circular reference resolving $args{type} $key"
      if $args{flags}{$key}++;

   my $rv;
   my $ref = ref $spec;
   if (! $ref) { # scalar, treat as string
      if (substr($spec, 0, 1) eq '@') { # import from somewhere
         $rv = load_from_dibspack($spec, %args);
      }
      else {
         $rv = exists $args{config}{$spec} ? $args{config}{$spec}
            :  exists $args{parser}        ? $args{parser}->($spec)
            :                                undef;
         defined $rv or ouch 400, "unknown $args{type} $spec";
         $rv = inflate($rv, %args);
      }
   }
   elsif ($ref eq 'ARRAY') {
      $rv = [
         map {
            my $item = inflate($_, %args);
            ref($item) eq 'ARRAY' ? $item->@* : $item; # "flatten"
         } $spec->@*
      ];
   }
   elsif ($ref eq 'HASH') {
      if (exists $spec->{extends}) {
         my $exts = inflate(delete($spec->{extends}), %args);
         my %exts = map { $_->%* }
            ref($exts) eq 'ARRAY' ? reverse($exts->@*) : $exts;
         $spec->%* = (%exts, $spec->%*);
      }
      $rv = $spec;
   }
   else { ouch 500, 'something still not implemented here?'; }

   # free this item up for possible reuse
   delete $args{flags}{$key};

   return $rv;
}

sub resolve_dibspack ($spec, %args) {
   if (!ref $spec) {
      my ($name, $path, $datapath) = $spec =~ m{
         \A \@            # this can be removed
         ([^/#]+)         # name of dibspack
         (?: /  ([^#]*))? # path (optional
         (?: \# (.*))?    # fragment -> datapath
         \z
      }mxs;
      ouch 400, "invalid dibspack locator $spec" unless defined $name;
      $path = undef unless length($path // '');
      $datapath = undef unless length ($datapath // '');
      $spec = { '@' => $name, path => $path, datapath => $datapath };
   }
   elsif (exists($spec->{dibspack}) && blessed($spec->{dibspack})) {
      return $spec;
   }
   return {
      dibspack => $args{dibspack_factory}->item($spec->{'@'}, %args),
      path     => $spec->{path},
      datapath => $spec->{datapath},
   };
}

sub load_from_dibspack ($spec, %as) {
   my $p = resolve_dibspack($spec, dynamic_zone => HOST_DIBSPACKS, %as);
   my @path = defined($p->{path}) ? $p->{path} : ();
   my $path = $p->{dibspack}->location->host_path(@path);
   ouch 404, "missing file $path" unless $path->exists;
   my $whole = LoadFile($path);

   # ensure the needed data are there
   my $data = data_in($whole, $p->{datapath});

   my $zf = $as{zone_factory} // $as{dispack_factory}->zone_factory;
   my $cf = $whole->{&DIBSPACKS} // {};
   my $ldps = Dibs::Pack::Factory->new(config => $cf, zone_factory => $zf);
   return inflate($data, %as, dispack_factory => $ldps, config => $cf);
}

sub data_in ($data, $datapath) {
   return $data unless defined $datapath;
   for my $step (split m{\.}mxs, $datapath) {
      my $ref = ref $data;
      if ($ref eq 'HASH') {
         ouch 400, "missing step '$step' in hash"
           unless exists $data->{$step};
         $data = $data->{$step};
      }
      elsif ($ref eq 'ARRAY') {
         ouch 400, "cannot step '$step' in array"
           unless $step =~ m{\A (?: 0 | -? [1-9]\d*) \z}mxs;
         ouch 404, "out of range index $step"
           if ($step > $#$step) || (-$step > $step->@*);
         $data = $data->[$step];
      }
      elsif (! $ref) {
         ouch 400, "cannot step '$step' into a scalar";
      }
      else {
         ouch 500, "unsupported ref '$ref' in data";
      }
   }
   return $data;
}

sub flatten_array ($aref, $flags = {}) {
   map {
      if (ref($_) eq 'ARRAY') {
         my $key = refaddr $_;
         ouch 400, 'circular dependency flattening array'
            if $flags->{$key}++;
         my @retval = flatten_array($_, $flags);
         delete $flags->{$key};
         @retval;
      }
      else { $_ }
   } $aref->@*;
}

1;
