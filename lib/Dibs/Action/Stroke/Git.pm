package Dibs::Action::Stroke::Git;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Config ':constants';
use Dibs::Action::Stroke::Pack ();
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($class, %args) {
ouch 500, 'do not use this';
   my %spec = $args{spec}->%*;
   $spec{pack} = {
      type => GIT,
      origin => $spec{origin},
      ref    => $spec{ref},
   };
   return Dibs::Action::Stroke::Pack->create(%args, spec => \%spec);
}

sub parse ($class, $url) { return { origin => $url } }

1;
__END__
