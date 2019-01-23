package Dibs;
use 5.024;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Path::Tiny qw< path cwd >;
use Ouch qw< :trytiny_var >;
use Try::Catch;
use POSIX qw< strftime >;
use Scalar::Util qw< refaddr blessed >;
use experimental qw< postderef signatures >;
use Storable 'dclone';
use Module::Runtime 'use_module';
use Moo;
use Data::Dumper;
local $Data::Dumper::Indent = 1;
no warnings qw< experimental::postderef experimental::signatures >;
{ our $VERSION = '0.001'; }

use Dibs::Config ':constants';
use Dibs::Action::Factory;
use Dibs::Pack::Factory;
use Dibs::Zone::Factory;

with 'Dibs::Role::EnvCarrier';

has action_factory => (is => 'ro', required => 1);
has allow_dirty    => (is => 'ro', default  => 0);
has name           => (is => 'lazy');
has pack_factory   => (is => 'ro', required => 1);
has project_dir    => (is => 'ro', required => 1);
has variables      => (is => 'ro', default => sub { return {} });
has zone_factory   => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   %args = dclone(\%args)->%*;
   my %retval;

   $retval{name} = $args{name} if defined $args{name};

   # Allow acting in a dirty situation?
   $retval{allow_dirty} = $args{dirty} ? 1 : 0;

   # Project directory
   ouch 400, 'missing required value for project_dir'
     unless defined $args{project_dir};
   my $pd = $retval{project_dir} = path($args{project_dir})->absolute;

   # Zones factory
   my $zone_specs  = $args{zone_specs} // DEFAULTS->{zone_specs_for};
   my $zone_groups = $args{zone_groups} // DEFAULTS->{zone_names_for};
   my $zf          = $retval{zone_factory} = Dibs::Zone::Factory->new(
      project_dir    => $pd,
      zone_specs_for => $zone_specs,
      zone_names_for => $zone_groups,
   );

   # Pack factory
   my $pf = $retval{pack_factory} = Dibs::Pack::Factory->new(
      config       => ($args{packs} // {}),
      zone_factory => $zf,
   );

   # Action factory
   my $af = $retval{action_factory} = Dibs::Action::Factory->new(
      config       => ($args{actions} // {}),
      pack_factory => $pf,
      zone_factory => $zf,
   );

   # variables ned expansion but some "named ones" are also saved in case
   # of inclusion... future stuff FIXME
   $retval{variables} = __expand_variables(\%args);

   return \%retval;
} ## end sub BUILDARGS

sub _build_name ($self) {
   require Dibs::RandomName;
   return Dibs::RandomName::random_name();
}

sub instance ($self, $args) { $self->action_factory->instance($args) }

sub sketch ($self, $as) { $self->instance({actions => [$as->@*]}) }

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

sub __eval_vars ($opts, $name, @args) {
print {*STDERR} "$name(@args)\n";
   $name = 'dvf_' . $name; # "magic value" for prefix
   for my $package ($opts->{packages}->@*) {
      my $function = $package->can($name) or next;
      my @expanded_args = map {
         ref $_ eq 'ARRAY' ? __eval_vars($opts, $_->@*) : $_
      } @args;
print {*STDERR} " --> $name(@expanded_args)\n";
      return $function->($opts, @expanded_args);
   }
   ouch 400, "unhandled variables expansion function '$name'";
}


1;

__END__
