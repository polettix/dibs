package Dibs::Action::Stroke::Src;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Config ':constants';
use Dibs::Action::Stroke ();
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($class, %args) {
   my $path = $args{spec}{path} or ouch 400, 'no path for src type stroke';
   my $zone = $args{factory}->zone_factory->item(SRC);
   $args{path} = $zone->container_path($path);
   return Dibs::Action::Stroke->create(%args);
}

# fixme it might be DWIMmed a bit
sub parse ($class, $path) { return {path => $path} }

1;
__END__
