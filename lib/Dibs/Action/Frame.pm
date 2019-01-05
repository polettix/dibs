package Dibs::Action::Frame;
use 5.024;
use Ouch ':trytiny_var';
use Try::Catch;
use Dibs::Docker qw< cleanup_tags docker_tag docker_rmi >;
use Log::Any '$log';
use Moo;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

with 'Dibs::Role::Action';

has image_name => (is => 'ro', default => '');
has tags => (is => 'ro', default => sub {[]}, coerce => \&_tags);
has '+output_char' => (default => '+');

sub execute ($self, $args = undef) {
   defined(my $image = $args->{image})
     or ouch 400, 'no image to frame';
   my @tags;
   try {
      my $name = $self->image_name;
      my %done = ($image => 1);
      my $keep;
      for my $tag ($self->tags->@*) {
         my $dst = ($tag eq '*')    ? "$name:$args->{run_tag}" 
            : ($tag eq ':default:') ? $image
            : ($tag =~ m{:}mxs)     ? $tag 
            :                         "$name:$tag";
         $keep = $image if $dst eq $image;
         next if $done{$dst}++;
         docker_tag($image, $dst);
         push @tags, $dst;
      }

      # everything went OK, I can set relevant variables in $args
      $args->{tags} = \@tags;
      $args->{keep} = $keep;
   }
   catch {
      my $e = $_;
      cleanup_tags(@tags);
      die $e; # rethrow exception
   };

   return $args;
}

sub parse ($self, $type, $tag) { return {type => $type, tags => [$tag]} }

sub _tags ($tag) { return ref($tag) eq 'ARRAY' ? $tag : [$tag] }

1;
__END__
