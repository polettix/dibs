package Dibs::Action::Sketch;
use 5.024;
use Ouch ':trytiny_var';
use Log::Any '$log';
use Try::Catch;
use Dibs::Action;
#use Dibs::Config ':constants';
use Dibs::Zone::Factory;
use Dibs::Docker 'cleanup_tags';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

has actions => (is => 'ro', default => sub { return [] });
has '+output_char' => (is => 'ro', default => '=');

around create => sub ($orig, $class, %args) {
   ouch 400, 'cannot create a sketch without a specification'
     unless defined $args{spec};

   my ($spec, $factory, $factory_args) = @args{qw< spec factory args >};
   my $i = 0;
   my $name = $spec->{name} // $factory_args->{name} // '';
   my @actions = map {
      ++$i;
      Dibs::Action->create($_, $factory, $factory_args->%*, name => "$name/$i");
   } ($spec->{actions} // [])->@*;
   return $class->$orig(%args, spec => {$spec->%*, actions => \@actions});
};

sub draw ($self, %args) {
   my $args = \%args;
   my $zf = $args->{zone_factory}
      //= Dibs::Zone::Factory->default($args->{project_dir});
   $self->_ensure_volumes($args->{volumes} //= $self->_volumes($zf));
   try {
      $self->execute($args);
   }
   catch {
      cleanup_tags($args->{image}) if defined $args->{image};
      die $_; # rethrow
   };
   my @tags = ($args->{tags} // [])->@*;
   if (defined $args->{keep}) {
      unshift @tags, $args->{keep};
   }
   elsif (defined $args->{image}) {
      cleanup_tags($args->{image});
   }
   say for @tags;
   return $args;
}

sub _ensure_volumes ($self, $groups) {
   $_->[0]->mkpath for $groups->@*;
   return $self;
}

sub _volumes ($self, $zone_factory) {
   return [
      map {
         [$_->host_path, $_->container_path, ($_->writeable ? 'rw' : 'ro')]
      } $zone_factory->items('volumes')
   ];
}

# just iterate over sub-actions
sub execute ($self, $args = undef) {
   $args //= {};
   my $name = $self->name('(unknown)');
   my $id = 0;
   my @outputs;
   for my $action ($self->actions->@*) {
      $id++;
      $action->output_marked(
         verbose => $args->{verbose},
         name => "($name/$id)"
      );
      my $oargs = $action->execute($args);
      push @outputs, [$action->type, delete $oargs->{out}];
   }
   $args->{out} = \@outputs;
   return $args;
}

1;
__END__
