package Dibs::Pack::Subpack;
use 5.024;
use Ouch ':trytiny_var';
use experimental qw< postderef signatures >;
use Moo;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Pack::Instance;
use Dibs::Config ':constants';

sub create ($self, %args) {
   my ($spec, $factory) = @args{qw< spec factory >};
   my ($parent_name, $path) = map {
      $spec->{$_} // ouch 400, "missing '$_' in subpack"
   } qw< parent path >;
   my $parent   = $factory->item($parent_name, %args);
   my $location = $parent->location->sublocation($path);
   my $id       = SUBPACK . '/' . $parent->id;
   my $fetcher  = sub { $parent->materialize };

   return Dibs::Pack::Instance->new(
      $spec->%*,    # anything from the specification, with overrides below
      id       => $id,
      fetcher  => $fetcher,
      location => $location,
   );
} ## end sub create

1;
__END__
