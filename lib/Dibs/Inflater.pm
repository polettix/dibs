package Dibs::Inflater;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Scalar::Util qw< refaddr >;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

use Exporter 'import';
our @EXPORT_OK = qw< expand_hash flatten_array >;
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

sub __get_from_hash ($key, $hash) {
   my %seen;
   while (defined($key) && (!ref($key))) {
      return $key unless exists $hash->{$key};
      ouch 400, 'circular reference', {what => 'hash', name => $key}
         if $seen{$key}++;
      $key = $hash->{$key};
   }
   return $key;
}

sub expand_hash ($hash, $definition_for, $flags = {}) {
   defined(my $ds = delete($hash->{extends})) or return;
   $definition_for //= {};
   for my $source (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) {
      my $defaults = __get_from_hash($source, $definition_for);
      ref($defaults) eq 'HASH'
         or ouch 500, 'missing resolution', {hash => $source};

      # protect aginst circular dependencies
      my $id = refaddr($defaults);
      if ($flags->{$id}++) {
         my $name = ref($source) ? 'internal reference' : $source;
         ouch 400, "circular reference", {what => 'hash', name => $name};
      }

      # $defaults will hold the defaults to be merged into $hash. Make
      # sure to recursively resolve its defaults though
      expand_hash($defaults, $definition_for, $flags);

      # merge hashes and proceed to next default
      $hash->%* = ($defaults->%*, $hash->%*);

      # the same default might be ancestor to multiple things
      delete $flags->{$id};
   } ## end for my $source (ref($ds...))
   return $hash;
} ## end sub __expand_extends

sub flatten_array ($aref, $href, $flags = {}) {
   my $id = refaddr $aref;
   ouch 400, "circular reference", {what => 'array'}
     if $flags->{$id}++;

   my @retval = map {
      defined(my $item = __get_from_hash($_, $href))
        or ouch 400, "missing resolution", {what => 'array', name => $_};
      my $ref = ref $item;
      if ($ref eq 'ARRAY') {
         flatten_array($item, $href, $flags)->@*;
      }
      else {
         expand_hash($item, $href) if $ref eq 'HASH';
         Dibs::Action->create($item);
      }
   } $aref->@*;

   delete $flags->{$id};
   return \@retval;
}

1;
