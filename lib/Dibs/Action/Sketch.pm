package Dibs::Action::Sketch;
use 5.024;
use Dibs::Action;
use Moo;

with 'Dibs::Role::Action';

has actions => (is => 'ro', default => sub { return [] });

sub create ($class, %args) {
   ouch 400, 'cannot create a sketch without a specification'
     unless defined $args{spec};

   # $spec is the recipe to generate the sketch
   # $factory is what we can use to generate actions (or their proxies),
   #   it triggered create() as well most probably
   # $factory_args is what we inherited, e.g. might contain 'flags' for
   #   circular dependency avoidance
   my ($spec, $factory, $factory_args) = @args{qw< spec factory args >};

   my @actions = map {
      Dibs::Action->create($_, $factory, $factory_args);
   } ($spec->{actions} // [])->@*;

   return $class->new(
      name => ($spec->{name} // $factory_args->{name}),
      actions => \@actions,
      ancestors => $factory_args->{ancestors},
   );
}

# just iterate over sub-actions
sub draw ($self, $args = undef) {
   $args //= {};
   my $name = $self->name('(unknown)');
   my $id = 0;
   for my $action ($self->actions->@*) {
      $id++;
      $action->output(verbose => $args->{verbose}, name => "($name/$id)");
      $action->draw($args);
   }
   return $args;
}

1;
__END__
