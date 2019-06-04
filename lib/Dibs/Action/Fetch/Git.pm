package Dibs::Action::Fetch::Git;
use 5.024;
use Log::Any '$log';
use Dibs::Config ':constants';
use Ouch ':trytiny_var';
use Try::Catch;
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

has '+output_char' => (default => '<');
has args   => (is => 'ro', default => sub { return [] });
has path   => (is => 'ro', required => 1);
has origin => (is => 'ro', required => 1);

=begin typical

actions:
   whatever:
      type: git
      origin: git://...
      ref: v1
      name: xxx
      # will be put in src

=end typical

=cut


around create => sub ($orig, $class, %args) {
   my %spec =
      (ref($args{spec}) ? $args{spec} : $class->parse($args{spec}))->%*;

   # normalize the origin
   my $origin = $spec{origin};
   if (length(my $ref = $spec{ref} // '')) {
      ouch 400, 'cannot specify ref and fragment in URL'
         if $origin =~ m{\#}mxs;
      $origin .= '#' . $ref;
   }
   $spec{origin} = $origin;

   # establish target path
   my $src_zone = $args{factory}->zone_factory->item(SRC);
   my @path = defined $spec{path} ? $spec{path} : ();
   $spec{path} = $src_zone->host_path(@path);

   return $class->$orig(%args, spec => \%spec);
};

sub parse { ... }

sub execute ($self, $args = undef) {
   my $origin = $self->origin;
   my $local_dir = $self->path;
   $self->output("git: $origin -> $local_dir");
   require Dibs::Git;
   Dibs::Git::fetch($origin, $local_dir);
   return $args;
}


1;
__END__
