package Dibs::Role::Action;
use 5.024;
use Ouch qw< :trytiny_var >;
use Dibs::Output;
use Moo::Role;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has ancestors => (is => 'ro', default => sub { return [] });
has _name => (is => 'ro', default => undef, init_arg => 'name');

sub name ($self, $default = '') { $self->_name // $default }
sub _prefix ($self) { join ' -> ', map { $_->name } $self->ancestors->@* }
sub fullname ($self, $default = '') {
   my $prefix = $self->_prefix;
   my $n = $self->name($default);
   return length($n) ? "$prefix -> $n" : $prefix;
}

sub output ($self, %args) {
   my $char = $self->can('output_char') ? $self->output_char : ' ';
   my $type = $self->type;
   my $is_verbose = $args{verbose};
   my $def = $args{name}; # default name
   my $name = $is_verbose ? $self->fullname($def) : $self->name($def);
   ARROW_OUTPUT($char, "$type $name");
   return;
}

sub type ($self) { lc(ref $self) =~ s{\A.*::}{}rmxs }

1;
