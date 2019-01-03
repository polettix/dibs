package Dibs::App;
use 5.024;
use Try::Catch;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path cwd >;
use Scalar::Util 'blessed';
use Data::Dumper;
use POSIX 'strftime';

use Exporter 'import';
our @EXPORT_OK = qw< main initialize draw >;

use Dibs ();
use Dibs::Config ':all';
use Dibs::Get ();
use Dibs::Output;
use Dibs::Zone          ();
use Dibs::Zone::Factory ();

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub initialize (@as) {
   set_logger();    # initialize with defaults

   my $cmdenv = get_config_cmdenv(\@as);
   set_logger($cmdenv->{logger}->@*) if $cmdenv->{logger};

   # this is where we expect to find the configuration file
   my $cnfp = path($cmdenv->{config_file});

   # freeze the zone factory with what available now
   my $zone_factory = $cmdenv->{zone_factory}
     = Dibs::Zone::Factory->new($cmdenv->%*);
   my $src_dir = $zone_factory->zone_for(SRC)->host_base;

   my $cloned;
   $cloned = origin_onto_src($cmdenv, 'early ') && 1
     if defined($cmdenv->{origin}) || $src_dir->subsumes($cnfp);

   # start looking for the configuration file, refer it to the project dir
   # if relative, otherwise leave it as is
   $cnfp = $src_dir->child($cmdenv->{config_file})
     if (!$cnfp->exists) && $cloned;

   ouch 400, 'no configuration file found' unless $cnfp->exists;
   OUTPUT("base configuration from: $cnfp");

   my $overall = add_config_file($cmdenv, $cnfp);
   $overall->{zone_factory} = $zone_factory;

   # last touch to the logger if needed
   set_logger($overall->{logger}->@*) if $overall->{logger};

   $overall->{run_variables} = {
      DIBS_ID => strftime("%Y%m%d-%H%M%S-$$", gmtime),
   };

   # clone if necessary and not already done
   origin_onto_src($overall) if defined($overall->{origin}) && !$cloned;

   return $overall;
} ## end sub initialize (@as)

sub main (@as) {
   my $config = {};
   try {
      $config = initialize(@as);
      draw($config);
      return 0;
   } ## end try
   catch {
      $log->fatal(ref($_) && $config->{verbose} ? $_->trace : bleep);
      return 1;
   };
} ## end sub main (@as)

sub draw ($config) {
   my $dibs = Dibs->new($config);
   my $run_variables = $config->{run_variables};
   my $run_tag = $run_variables->{DIBS_ID};
   my $name = $dibs->name;

   $dibs->append_envile($run_variables);
   return $dibs->sketch($config->{do})->draw(
      env_carriers => [$dibs],
      project_dir  => $dibs->project_dir,
      zone_factory => $dibs->zone_factory,
      run_tag => $run_tag,
      to => "$name:$run_tag",
      verbose => $config->{verbose},
   );
}

sub origin_onto_src ($config, $early = '') {
   my $origin = $config->{origin} // '';
   $origin = cwd() . $origin
     if ($origin eq '') || ($origin =~ m{\A\#.+}mxs);

   my $src_dir = $config->{zone_factory}->zone_for(SRC)->host_base;
   my $dirty   = $config->{dirty} // undef;

   ARROW_OUTPUT('=', "${early}clone of origin $origin (dirty: " . ($dirty ? 'allowed': 'not allowed') . ')');
   Dibs::Get::get_origin($origin, $src_dir,
      {clean_only => !$dirty, wipe => 1});

   return $src_dir;
} ## end sub origin_onto_src ($config)

sub set_logger (@args) {
   state $set = 0;
   return if $set++ && !@args;
   my @logger = scalar(@args) ? @args : DEFAULTS->{logger}->@*;
   Log::Any::Adapter->set(@logger);
} ## end sub set_logger (@args)

1;

__END__
