package Dibs::Action::Log;
use 5.024;
use Data::Dumper;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

sub execute ($self, $args = undef) {
   $self->output(Dumper $args);
   $self->output_marked(prefix => 'end of ');
   return $args;
}

sub parse ($self, $raw) { return {name => $raw} }

sub output_footer ($self) { $self->output_body('*** END OF LOG ***') }

1,
__END__
