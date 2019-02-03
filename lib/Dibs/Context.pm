package Dibs::Context;
use 5.024;
use Ouch qw< :trytiny_var >;
use Log::Any qw< $log >;
use Moo;
use Storable 'dclone';
use Module::Runtime 'use_module';
use Try::Catch;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Action::Factory;
use Dibs::Pack::Factory;

has _factory_for => (is => 'ro', required => 1, init_arg => 'factory_for');
has variables   => (is => 'ro', default => sub { return {} });

sub factory_for ($self, $type) {
   $type = use_module($type)->type if $type =~ m{::}mxs;
   return $self->_factory_for->{$type};
}

sub __filter (@args) {
   my %iargs = (@args && ref $args[0]) ? $args[0]->%* : @args;
   my @from_file = qw< actions packs variables variables_expanders >;
   my @from_parent = qw< named_variables run_variables zone_factory >;
   return map { $_ => $iargs{$_} }
     (@from_file, @from_parent);
}

sub BUILDARGS ($class, @args) {
   my %args = __filter(@args);
   my $zf = delete $args{zone_factory}
     or ouch 400, 'no zone_factory passed to context builder';

   # become owner of the stuff
   %args = dclone({%args})->%*;
   my %retval;
   my @factories;

   # Pack factory
   push @factories, my $pf = Dibs::Pack::Factory->new(
      config       => ($args{packs} // {}),
      zone_factory => $zf,
   );

   # Action factory
   push @factories, my $af = Dibs::Action::Factory->new(
      config       => ($args{actions} // {}),
      pack_factory => $pf,
      zone_factory => $zf,
   );

   $retval{factory_for} = { map { $_->type => $_ } @factories };

   # variables need expansion but some "named ones" are also saved in case
   # of inclusion...
   $retval{variables} = __expand_variables(\%args);

   return \%retval;
} ## end sub BUILDARGS

sub __eval_vars ($opts, $name, @args) {
   $name = 'dvf_' . $name; # "magic value" for prefix
   for my $package ($opts->{packages}->@*) {
      my $function = $package->can($name) or next;
      my @expanded_args = map {
         ref $_ eq 'ARRAY' ? __eval_vars($opts, $_->@*) : $_
      } @args;
      return $function->($opts, @expanded_args);
   }
   ouch 400, "unhandled variables expansion function '$name'";
}

sub __expand_variables ($cfg) {
   defined(my $variables = $cfg->{variables}) or return {};

   # load packages with functions for variable expansion
   my $packages = $cfg->{variables_expanders} // ['Dibs::Variables'];
   for my $package ($packages->@*) {
      try { use_module($package) }
      catch { ouch 400, "cannot load package $package" };
   }

   # iterate through definitions
   my $nv = $cfg->{named_variables} // {};
   my $opts = {
      packages => $packages,
      run_variables => $cfg->{run_variables},
      named_variables => $nv,
   };
   for my $var ($variables->@*) {
      my $ref = ref $var;
      if ($ref eq 'ARRAY') {
         $var = __eval_vars($opts, $var->@*);
      }
      elsif ($ref eq 'HASH') {
         for my $key (keys $var->%*) {
            my $value = $var->{$key};
            $value = $var->{$key} = __eval_vars($opts, $value->@*)
              if ref $value eq 'ARRAY';
            $nv->{$key} = $value;
         }
      }
   } ## end for my $var ($variables...)

   return $nv;
} ## end sub adjust_default_variables ($overall)

1;
__END__
