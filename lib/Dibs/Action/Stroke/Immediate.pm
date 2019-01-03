package Dibs::Action::Stroke::Immediate;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Config ':constants';
use Dibs::Action::Stroke::Pack ();
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($class, %args) {
ouch 500, 'do not use this';
   my %spec = $args{spec}->%*;
   defined(my $program = $spec{program} // $spec{run})
      or ouch 400, 'immediate: neither "program" nor "run" found';
   $spec{pack} = { type => IMMEDIATE, program => $program };
   delete $spec{path}; # no point in having it
   return Dibs::Action::Stroke::Pack->create(%args, spec => \%spec);
}

sub parse ($class, $raw) { return { program => $raw } }

1;
__END__
