package Dibs::Process;
use 5.024;
use Ouch qw< :trytiny_var >;
use Moo;
use Scalar::Util qw< refaddr >;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::EnvCarrier';

has _actions => (
   is => 'ro',
   default => sub { return [] },
   init_arg => 'actions',
   isa => \&_isa_actions,
);
has actions => (is => 'lazy', init_arg => undef);
has commit => (is => 'ro', default => undef);
has from => (is => 'ro', required => 1);

sub _build_actions ($self) {
   my $actions = $self->_actions;
   return [] unless defined $actions;
   return $actions if ref($actions) eq 'ARRAY';
   return $actions->();
}

sub _isa_actions ($actions) {
   ouch 'invalid action' if defined($actions)
      && ! grep { ref($actions) eq $_ } qw< ARRAY CODE >;
}

sub actions_inflater ($class, $actions_list, $adf) {
   ouch 400, 'actions_flattener can be called only as class method'
      if ref $class;
   my $actions = [$actions_list->@*];
   return sub {
      my @stack = {queue => $actions};
      my @retval;
      my %seen;    # circular inclusion avoidance
    ITEM:
      while (@stack) {
         my $queue = $stack[-1]{queue};
         if (scalar($queue->@*) == 0) {
            my $exhausted_frame = pop @stack;

            # the "parent" of this frame can be removed from circular
            # inclusion avoidance
            delete $seen{$exhausted_frame->{parent}}
              if exists $exhausted_frame->{parent};

            next ITEM;
         } ## end if (scalar($queue->@*)...)

         my $item = shift $queue->@*;
         my $ref  = ref $item;
         if ($ref eq 'ARRAY') {    # do "recursive" flattening
            my $id = refaddr($item);
            ouch 400, "circular reference in actions for $step"
              if $seen{$id}++;

            # this $id will trigger circular inclusion error from now
            # until the stack frame is eventually removed
            push @stack, {parent => $id, queue => [$item->@*]};

            next ITEM;
         } ## end if ($ref eq 'ARRAY')
         elsif ($ref eq 'HASH') {
            __expand_extends($item, ACTIONS, $adf);
            push @retval, Dibs::Action->create($item, $self);
            next ITEM;
         }
         elsif ((!$ref) && exists($adf->{$item})) {
            unshift $queue->@*, $adf->{$item};
            next ITEM;
         }
         elsif (!$ref) {
            push @retval, Dibs::Action->create($item, $self);
            next ITEM;
         }
         else {
            ouch 400, "unknown action of type $ref";
         }
      } ## end ITEM: while (@stack)
   } ## end if (!$afor->{$step})

   };
}

1;
