package Dibs::Pack::Dynamic;
use 5.024;
use Dibs::Config ':constants';
use Dibs::Pack::Instance;
use Moo;
use Module::Runtime 'use_module';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($self, %args) {
   my ($spec, $factory, $zone) = @args{qw< spec factory dynamic_zone >};
   my $type    = $spec->{type};
   my $fetcher = use_module('Dibs::Fetcher::' . ucfirst $type)->new($spec);
   my $id      = $type . '/' . $fetcher->id;

   # resolve the zone (possibly just a name here) into a Dibs::Zone
   $zone = $factory->zone_factory->zone_for($zone // PACK_HOST_ONLY);

   return Dibs::Pack::Instance->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      fetcher  => $fetcher,
      location => {base => $id, zone => $zone},
   );
} ## end sub create

1;
__END__
