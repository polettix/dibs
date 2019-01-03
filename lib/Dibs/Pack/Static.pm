package Dibs::Pack::Static;
use 5.024;
use Ouch qw< :trytiny_var >;
use Path::Tiny 'path';
use Dibs::Pack::Instance;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($self, %args) {
   my ($spec, $factory, $zone_name ) = @args{qw< spec factory zone_name >};
   my $type = $spec->{type};
   $zone_name //= $type;

   my $zone = $factory->zone_factory->zone_for($zone_name);
   my %location = (zone => $zone);

   my $fullpath; # useful for assigning an identifier to this pack
   if (defined(my $base = $spec->{base} // $spec->{raw} // undef)) {
      $location{base} = $base;
      $fullpath = path($base);
   }
   if (defined(my $path = $spec->{path} // undef)) {
      $location{path} = $path;
      $fullpath = $fullpath ? $fullpath->child($path) : path($path);
   }

   # if $fullpath is not true, none of base(/raw) or path was set
   $fullpath or ouch 400, "invalid base/path for $type pack";

   # build %subargs for call to Dibs::Pack::Instance
   my %instance_args = (
      id => "$type:$fullpath",
      location => \%location,
   );

   # name presence is optional, rely on default from class if absent
   $instance_args{name} = $spec->{name} if exists $spec->{name};

   return Dibs::Pack::Instance->new(%instance_args);
}

sub parse ($self, $type, $raw) { return {type => $type, base => $raw} }

1;
__END__
