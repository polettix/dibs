package Dibs::Action::Stroke::Inside;
use 5.024;
use Dibs::Action::Stroke;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub create ($class, %args) {
   use Data::Dumper;
   local $Data::Dumper::Indent = 1;
   say Dumper {yay => \%args};
   Dibs::Action::Stroke->create(%args);
}

sub parse ($class, $raw) { return {path => $raw} }

1;
__END__
