package Dibs::Factory;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Config ':constants';
use Module::Runtime 'use_module';
use Try::Catch;
use Scalar::Util 'refaddr';
use Guard;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has ancestors => (is => 'ro', default => sub { return [] });
has dibspack_factory => (is => 'ro', required => 1);
has context => (is => 'ro', default => undef);
has name => (is => 'ro', default => undef);

with 'Dibs::Role::Factory';

sub _add_context ($self, $feedback) {
   defined(my $ctx = $self->context) or return $feedback;
   return "$feedback (\@$ctx)";
}

sub _create_instance ($self, $type, %args) {
   ouch 400, 'missing action type' unless defined $type;

   state $class_for = {
      &SKETCH => 'Dibs::Sketch',
      map { $_ => 'Dibs::Stroke' }
         (GIT, HTTP, IMMEDIATE, INSIDE, PROJECT, SRC),
   };
   my $class = $class_for->{$type} // $type;

   try { use_module($class) }
   catch { ouch 400, "invalid action type '$type'" };

   return $class->create(%args, factory => $self, type => $type);
}

sub instance ($self, $x, %args) {
   # FIXME add protection against circular dependency here or where it
   # belongs

   my $ref = ref $x;
   return $self->_instance_for_array($x, \%args) if $ref eq 'ARRAY';
   return $self->_instance_for_hash($x, \%args) if $ref eq 'HASH';

   ouch 400, "invalid input for instance ($x)" if $ref ne '';

   return $self->_instance_for_rawspec($x, \%args) if $x =~ m{ [#] }mxs;
   return $self->_instance_for_remote($x, \%args)  if $x =~ m{ [@] }mxs;
   return $self->_instance_for_name($x, \%args);
}

sub __check_circular ($args, $key, $feedback) {
   $args->{flags} //= {};
   ouch 400, "circular dependency at $feedback" if $args->{flags}{$key}++;
   return guard { delete $args->{flags}{$key} };
}

sub _instance_for_array ($self, $actions, $args) {
   my $feedback = $self->_add_context('array');
   my $guard = __check_circular($args, 'R' . refaddr($actions), $feedback);
   $self->_instance_for_hash({type => SKETCH, actions => $actions}, $args);
}

sub _instance_for_hash ($self, $spec, $args) {
   my $feedback = $self->_add_context('hash');
   my $guard = __check_circular($args, 'R' . refaddr($spec), $feedback);
   ouch 400, 'missing type in action specification'
     unless defined $spec->{type};
   $args->{name} //= $self->name;
   $self->_create_instance($spec->{type}, args => $args, spec => $spec);   
}

sub _instance_for_name($self, $name, $args) {
   my $key = $name;
   $key .= '@' . $self->context if defined $self->context;
   my $guard = __check_circular($args, "L$key", $self->_add_context($name));
   my $config = $self->_config;
   ouch 400, "missing '$name'" unless defined $config->{$name};

   # add this node as an indicator for redirection, in case we want to
   # show it in the breadcrumbs
   require Dibs::Redirection;
   $args->{ancestors} = [ # extend ancestors for recursion
      (($args->{ancestors} // $self->ancestors)->@*),
      Dibs::Redirection->new(id => $key, name => $name),
   ];

   # recurse, no need to go through a new proxy
   return $self->instance($config->{$name}, $args);
}

sub _instance_for_rawspec ($self, $spec, $args) { # only strokes allowed
   my $key = $self->_add_context($spec);
   my $guard = __check_circular($args, "D$key", $key);
   my ($type, $raw) = split m{ [#] }mxs, $spec, 2;
   $args->{name} //= $self->name;
   return $self->_create_instance($type, args => $args, raw => $raw);
}

sub _instance_for_remote ($self, $locator, $args) {
   my $feedback = $self->_add_context($locator);
   my $guard = __check_circular($args, "L$locator", $feedback);
   ouch 500, 'unimplemented';
}

sub _clone_ancestors ($self, $override) {
   return [($override // $self->ancestors)->@*];
}

1;
