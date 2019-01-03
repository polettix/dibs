package Dibs::Role::Action;
use 5.024;
use Ouch qw< :trytiny_var >;
use Dibs::Output;
use Moo::Role;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

requires qw< execute >;

has ancestors => (is => 'ro', default => sub { return [] });
has _name => (is => 'lazy', init_arg => 'name');
has output_char => (is => 'ro', default => ' ');

sub _build__name ($self) { return }

sub create ($class, %args) {

   # $spec is the recipe to generate the sketch
   # $factory is what we can use to generate actions (or their proxies),
   #   it triggered create() as well most probably
   # $factory_args is what we inherited, e.g. might contain 'flags' for
   #   circular dependency avoidance
   my ($spec, $factory_args) = @args{qw< spec args >};
   $spec = $class->parse($spec) unless ref $spec;

   my %constructor_args = (
      $spec->%*,
      ancestors => $factory_args->{ancestors},
   );
   if (defined(my $name = ($spec->{name} // $factory_args->{name}))) {
      $constructor_args{name} = $name;
   }
   return $class->new(%constructor_args);
}

sub fullname ($self, $default = '') {
   my $prefix = $self->_prefix;
   my $n = $self->name($default);
   return length($n) ? "($prefix) $n" : $prefix;
}

sub name ($self, $default = '') { $self->_name // $default }

sub output_marked ($self, %args) {
   my $char = $self->output_char;
   my $type = $self->type;
   my $is_verbose = $args{verbose};
   my $def = $args{name}; # default name
   my $name = $is_verbose ? $self->fullname($def) : $self->name($def);
   my $prefix = $args{prefix} // '';
   my $suffix = $args{suffix} // '';
   ARROW_OUTPUT($self->output_char, "$type $prefix$name$suffix");
   return;
}

sub output ($self, $message) { OUTPUT($message) }

sub _prefix ($self) { join ' -> ', map { $_->name } $self->ancestors->@* }

sub type ($self) { lc(ref $self) =~ s{\A.*::}{}rmxs }

1;
