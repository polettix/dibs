package Dibs::Run;
use 5.024;
use Carp;
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
use Log::Any qw< $log >;
use IPC::Run 'run';
use Ouch ':trytiny_var';
use Try::Catch;
no warnings qw< experimental::postderef experimental::signatures >;

use Dibs::Config ':constants';
use Dibs::Output;

use Exporter 'import';
our @EXPORT_OK = qw<
  run_command     assert_command
  run_command_out assert_command_out
  run_command_outerr
>;

sub __indenter ($n_indent = INDENT) {
   my $leftover = '';
   my $indenter = sub {
      my $text = $leftover . (@_ ? $_[0] : "\n");
      my @lines = split m{\n}mxs, $text;
      $leftover =
        $text =~ m{(?:\x{0a}\x{0d}?|\x{0d}\x{0a})\z}mxs ? '' : pop @lines;
      OUTPUT($_, $n_indent) for @lines;
   };
   return $indenter;
} ## end sub __indenter ($n_indent = INDENT)

sub _run_command ($command, $n_indent, $out = undef) {
   try {
      my $indenter = __indenter($n_indent);
      my @runargs = $out ? ($out, $indenter) : ($indenter, '2>&1');
      run $command, \undef, @runargs;
      $indenter->();    # "flush" any leftover
   } ## end try
   catch {
      ouch 500, "failed command (@$command) ($_)", $_;
   };

   return $?;
} ## end sub _run_command

sub run_command ($command, $n_indent = INDENT) {
   return _run_command($command, $n_indent);
}

sub run_command_out ($command, $n_indent = INDENT) {
   my $out;
   my $ecode = _run_command($command, $n_indent, \$out);
   return ($ecode, $out);
}

sub run_command_outerr ($command, $in = undef) {
   my ($out, $err);
   try {
      run $command, \$in, \$out, \$err;
   }
   catch {
      ouch 500, "failed command (@$command) ($_)", $_;
   };
   return ($?, $out, $err);
}

sub assert_command ($command, $n_indent = INDENT) {
   my $retval = run_command($command, $n_indent);
   return if $retval == 0;
   my ($exit, $signal) = ($retval >> 8, $retval & 0xFF);
   ouch 500, "command (@$command) failed, exitcode<$exit> signal<$signal>";
} ## end sub assert_command

sub assert_command_out ($command, $n_indent = INDENT) {
   my ($retval, $out) = run_command_out($command, $n_indent);
   return $out if $retval == 0;
   my ($exit, $signal) = ($retval >> 8, $retval & 0xFF);
   ouch 500, "command (@$command) failed, exitcode<$exit> signal<$signal>";
} ## end sub assert_command_out

1;
__END__
