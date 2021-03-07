package Dibs::Action::Stroke::Commit;
use 5.024;
use Ouch ':trytiny_var';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

{
   my @fields = qw< author changes cmd entrypoint label message user workdir >;

   has $_ => (is => 'ro', default => undef) for @fields;

   sub as_hash ($self) {
      return {
         map {
            my $v = $self->$_;
            defined($v) ? ($_ => $v) : ()
         } @fields
      };
   }
}

1;
__END__
