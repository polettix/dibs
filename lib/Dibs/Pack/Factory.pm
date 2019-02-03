package Dibs::Pack::Factory;
use 5.024;
use Ouch qw< :trytiny_var >;
use Scalar::Util qw< blessed refaddr >;
use Log::Any '$log';
use Module::Runtime 'use_module';
use Path::Tiny 'path';
use Dibs::Config ':constants';
use Dibs::Pack::Instance;
use Dibs::Context;
use YAML::XS;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Factory';

has _context_for => (is => 'lazy', init_arg => undef);

has zone_factory => (is => 'ro', required => 1);

sub _build__context_for ($self) { return {} }

sub _build__class_for ($self) {
   return {
      &GIT       => 'Dibs::Pack::Dynamic',
      &IMMEDIATE => 'Dibs::Pack::Dynamic',
      &HTTP      => 'Dibs::Pack::Dynamic',
      &INSIDE    => 'Dibs::Pack::Static',
      &PROJECT   => 'Dibs::Pack::Static::Project',
      &SRC       => 'Dibs::Pack::Static',
      &SUBPACK   => 'Dibs::Pack::Subpack',
   };
}

sub pack_factory ($self) { return $self }

sub normalize ($self, $spec, %args) {
   # DWIM-my stuff here
   if (! defined $spec->{type}) {
      $log->debug("no explicit type set");
      my $m;
      if (($m) = grep { exists $spec->{$_} } qw< run program >) {
         $spec->{type} = IMMEDIATE;
         $spec->{program} = delete $spec->{$m} if $m ne 'program';
      }
      elsif (($m) = grep { exists $spec->{$_} } SRC, INSIDE, PROJECT) {
         $spec->{type} = $m;
         $spec->{base} = delete $spec->{$m};
      }
      elsif (($m) = grep { exists $spec->{$_} } GIT, 'origin') {
         $spec->{type} = GIT;
         $spec->{origin} = delete $spec->{$m} if $m ne 'origin';
      }
   }

   my $ptype = $spec->{type} // '(still none defined)';
   $log->debug("normalized type: $ptype");

   return $spec;
}

around pre_inflate => sub ($orig, $self, $x, %args) {
   return $self->$orig($x, %args) if ref $x;
   return {type => GIT,  origin => $x} if $x =~ m{\A git://    }mxs;
   return {type => HTTP, URI => $x}    if $x =~ m{\A https?:// }mxs;
   return $self->$orig($x, %args); # turn to regular munging
};

sub _get_context ($self, $locator, $path, %args) {
   my $pack = $self->item($locator, dynamic_zone => PACK_HOST_ONLY, %args);
   my $host_path = $pack->host_path(defined $path ? $path : ());
   return $self->_context_for->{$host_path} //= do {
      $pack->materialize;
      Dibs::Context->new(LoadFile($host_path));
   };
}

sub get_sub_factory ($self, $spec, %args) {
   my $context = $self->_get_context($spec->@{qw< pack path >},
      zone_factory => $self->zone_factory, %args);
   return $context->factory_for->{$spec->{factory_type}};
}

1;
__END__
