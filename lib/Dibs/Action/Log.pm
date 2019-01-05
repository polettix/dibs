package Dibs::Action::Log;
use 5.024;
use Data::Dumper;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

has dump => (is => 'ro', default => undef);
has message => (is => 'ro', default => undef);
has '+output_char' => (is => 'ro', default => '~');

sub execute ($self, $args = undef) {
   $self->output(Dumper $args) if $self->dump;
   if (defined(my $message = $self->message)) {
      $self->output($message);
   }
   # $self->output_marked(prefix => 'end of ');
   return $args;
}

sub parse ($self, $type, $raw) { return {type => $type, message => $raw} }

1;
__END__
