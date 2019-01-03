package Dibs::Action::Stroke::Pack;
use 5.024;
use Ouch ':trytiny_var';
use Dibs::Action::Stroke ();
use Dibs::Config ':constants';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

has _instance => (is => 'ro', required => 1);
has _dibspack => (is => 'ro', required => 1);

sub AUTOLOAD ($self, @args) {
   my $method = (our $AUTOLOAD) =~ s{.*::}{}grmxs;
   my $instance = $self->_instance;
   return if $method eq 'DESTROY' && ! $instance->can('DESTROY');
   $self->_instance->$method(@args);
}

sub create ($class, %args) {
ouch 500, 'do not rely on this please';
   my ($factory, $factory_args, $spec) = @args{qw< factory args spec >};
   my $dibspack_factory = $factory->dibspack_factory;
   my $definition = $spec->{pack} // $spec->{dibspack};

   # strokes are saved where the container can reach 'em
   my $zone = $dibspack_factory->zone_factory->item(PROJECT);

   my $dibspack = $dibspack_factory->item(
      $definition,
      dynamic_zone => $zone,
      $factory_args->%*,
   );
   $args{path} = $dibspack->container_path($spec->{path});
   my $instance = Dibs::Action::Stroke->create(%args);
   return $class->new(_instance => $instance, _dibspack => $dibspack);
}

# fixme it might be DWIMmed a bit
sub parse ($class, $raw) { ouch 500, "dibspacks are complex beasts!" }

sub execute ($self, @args) {
   $self->_dibspack->materialize;
   return $self->_instance->execute(@args);
}

1;
__END__
