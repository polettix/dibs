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
has zone_factory   => (is => 'ro', required => 1);

sub BUILDARGS ($class, @args) {
   my %args = (@args && ref $args[0]) ? $args[0]->%* : @args;
   my %retval;

   # Allow acting in a dirty situation?
   $retval{dirty} = $args{dirty} ? 1 : 0;

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

   return \%retval;
} ## end sub BUILDARGS

sub _build_name ($self) {
   require Dibs::RandomName;
   return Dibs::RandomName::random_name();
}

sub instance ($self, $args) { $self->action_factory->instance($args) }

1;

__END__
