package Dibs::Cache;
use 5.024;
use Ouch ':trytiny_var';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has type => (is => 'ro', required => 1);
has _item_for => (
   is       => 'ro',
   init_arg => 'items',
   default  => undef,                               # set default in coerce
   coerce   => sub ($v) { defined($v) ? $v : {} },
   isa      => sub ($v) {
      ouch 500, 'invalid items, not a hash reference'
        unless ref($v) eq 'HASH';
   },
);

sub item ($self, $name, @value) {
   my $hash = $self->_item_for;
   $hash->{$name} = $value[0] if @value;
   return $hash->{$name} if exists $hash->{$name};
   my $type = $self->type;
   ouch 404, "missing $type '$name'";
} ## end sub item

sub contains ($self, $name) { exists $self->_item_for->{$name} }

sub names ($self) { return keys $self->_item_for->%* }


1;
