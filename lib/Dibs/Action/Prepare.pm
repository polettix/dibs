package Dibs::Action::Prepare;
use 5.024;
use Try::Catch;
use Ouch ':trytiny_var';
use Dibs::Docker qw< docker_tag >;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

has from => (is => 'ro', required => 1);
has '+output_char' => (default => '-');

sub _build__name ($self) { return '(from: ' . $self->from . ')' }

sub execute ($self, $args) {
   my $from = $self->from;
   defined(my $to = $args->{to})
     or ouch 400, 'no tagging target found';
   $self->output("tag $from to $to");
   try { docker_tag($from, $to) }
   catch { ouch 400, "cannot tag $from to $to. Build $from maybe?" };
   $args->{image} = $to;
   delete $args->{keep}; # will have to re-instate
   return $args;
}

sub parse ($self, $type, $raw) { return { type => $type, from => $raw } }

1,
__END__
