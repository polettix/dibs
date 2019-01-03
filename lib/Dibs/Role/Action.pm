package Dibs::Role::Action;
use 5.024;
use Ouch qw< :trytiny_var >;
use Dibs::Output;
use Moo::Role;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

requires qw< execute >;

has breadcrumbs => (is => 'ro', default => sub { return [] });
has _name => (is => 'lazy', init_arg => 'name');
has output_char => (is => 'ro', default => ' ');

sub _build__name ($self) { return }

# this is the default create, override if you need more stuff from %args
sub create ($class, %args) {
   return $class->new($args{spec}->%*);
}

sub fullname ($self, $default = '') {
   my $prefix = $self->_prefix;
   my $n = $self->name($default);
   return length($n) ? "$n ($prefix)" : $prefix;
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

sub _prefix ($s) { join ' -> ', map { $_->name } $s->breadcrumbs->@* }

sub type ($self) { lc(ref $self) =~ s{\A.*::}{}rmxs }

1;
