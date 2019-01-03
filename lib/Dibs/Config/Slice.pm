package Dibs::Config::Slice;
use 5.024;
use Ouch ':trytiny_var';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

extends 'Dibs::Cache';

around item => sub ($orig, $self, $name, @value) {
   return $self->$orig($name) unless @value;
   my $type = $self->type;
   ouch 500, "cannot set items in a configuration slice";
};

sub _recursive_item ($self, $item) {
   my %seen;
   while (!ref($item)) {
      last unless $self->contains($item);
      if ($seen{$item}++) {
         my $type = $self->type;
         ouch 400, "circular reference for $type '$item'";
      }
      $item = $self->item($item);
   }
   return $item;
}

sub _expanded_item ($self, $x, $flags = undef) {
   my $item = ref $x ? $x : $self->_recursive_item($self->item($x));
   return $item unless ref($item) eq 'HASH'; # this can be expanded
   defined(my $ds = delete($item->{extends})) or return $item;

   # two handy variables for meaningful errors
   my $type = $self->type;
   my $name = ref($x) ? 'internal hash' : "'$x'";

   # protect against circular dependencies before going on
   my $id = refaddr($item);
   ouch 400, "circular reference for $type '$name'" if $flags->{$id}++;

   for my $source (ref($ds) eq 'ARRAY' ? $ds->@* : $ds) {
      my $sname = ref($source) ? 'internal reference' : "'$source'";

      my $defaults = $self->_expanded_item($source);
      ouch 400, "expanding $type $name: $sname not yielding a hash"
         if ref($defaults) ne 'HASH';

      # merge hashes and proceed to next default
      $item->%* = ($defaults->%*, $item->%*);
   } ## end for my $source (ref($ds...))

   # this hash can be reused again from now on
   delete $flags->{$id};

   return $item;
} ## end sub __expand_extends

sub expanded_item ($self, $x) { return $self->_expanded_item($x) }

1;
