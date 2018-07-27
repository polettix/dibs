package Dibs::Output;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Log::Any qw< $log >;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Exporter 'import';

our @EXPORT_OK = (qw< RAW_OUTPUT ARROW_OUTPUT OUTPUT >);
our @EXPORT = @EXPORT_OK;

sub RAW_OUTPUT ($line) { $log->info($line) }

sub ARROW_OUTPUT ($arrow_str, $line) {
   my $length = INDENT - 2;
   my $stick = $arrow_str x int(1 + $length / length($arrow_str));
   RAW_OUTPUT(substr($stick, 0, $length) . '> ' . $line);
}

sub OUTPUT ($text, $n_indent = INDENT) {
   if ($n_indent) {
      my $indent = ' ' x $n_indent;
      RAW_OUTPUT(s{^}{$indent}rmxs) for split m{\n}mxs, $text;
      return;
   }
   RAW_OUTPUT($_) for split m{\n}mxs, $text;
   return;
}


1;
__END__


