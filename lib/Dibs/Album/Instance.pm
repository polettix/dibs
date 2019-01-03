package Dibs::Album::Instance;
use 5.024;
use Ouch ':trytiny_var';
use Try::Catch;
use Dibs::Inflater 'flatten_array';
use Dibs::Config ':constants';
use Dibs::Output;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::EnvCarrier';
with 'Dibs::Role::Identifier';

has sketches => (is => 'ro', required => 1);

sub BUILDARGS ($self, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   my $sections = [$args{sections}]; # flatten will help
   my ($album_factory, $sketch_factory, $dibspack_factory) = map {
      my $name = $_ . '_factory';
      ouch 400, "missing required argument $name"
        unless defined $args{$name};
      $args{$name};
   } qw< album sketch dibspack >;
   my @sketches;
   for my $section (flatten_array($sections, $args{flags} //= {})) {
      my $ref = ref $section;
      if (! $ref) {
         my ($type, $name) = split m{:}mxs, $section, 2;
         ($type, $name) = (SKETCH, $type) unless defined $name;
         if ($type eq ALBUM) {
            my $album = $album_factory->item($name, %args);
            push @sketches, $album->sketches->@*;
         }
         elsif ($type eq SKETCH) {
            push @sketches, $sketch_factory->item($name, %args);
         }
         else {
            ouch 400, "invalid album section of type $type";
         }
      }
   }
   return {%args, sketches => \@sketches};
}

sub draw ($self, %args) {
   ARROW_OUTPUT('>', 'album ' . $self->name);
   $args{env_carriers} = [ $self, ($args{env_carriers} // [])->@* ];
   $_->draw(%args) for $self->sketches->@*;
   return;
} ## end sub run

1;
