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

sub download_configuration_file ($config) {
   require Dibs::Pack::Factory;
   my $uri = $config->{config_file};
   my $pack = Dibs::Pack::Factory->new(
      config => {}, #{ foo => $config->{config_file} },
      zone_factory => $config->{zone_factory},
   )->item($config->{config_file});
   $pack->materialize;
   return $pack->host_path;
}

sub ensure_configuration_file ($config) {
   my $cnfp = $config->{config_file};
   my $cloned = 0;
   if ($cnfp =~ m{\A https?://}imxs) {
      # download and change $cnfp into absolute path
      $cnfp = download_configuration_file($config);
   }
   elsif (path($cnfp)->is_relative) {
      my $alien = $config->{alien};
      if (! $alien) {       # "developer" mode
         for my $base (cwd(), $config->{project_dir}) {
            my $candidate = $base->child($cnfp)->absolute;
            if ($candidate->exists) {
               $cnfp = $candidate;
               last;
            }
         }
      }
      elsif ($alien == 1) { # "alien" mode
         $cnfp = $config->{project_dir}->child($cnfp)->absolute;
      }
      else {                # "alien-alien" mode
         # check out src immediately... if so requested!
         if (defined $config->{origin}) {
            origin_onto_src($config, 'early ');
            $cloned = 1;
         }

         # in any case, "alien-alien" mode means dibs.yml in SRC
         my $src_dir = $config->{zone_factory}->zone_for(SRC)->host_base;
         $cnfp = $src_dir->child($cnfp)->absolute;
      }
   }
   return (path($cnfp), $cloned);
}

sub initialize (@as) {
   set_logger();    # initialize with defaults

   my $cmdenv = get_config_cmdenv(\@as);
   set_logger($cmdenv->{logger}->@*) if $cmdenv->{logger};

   # freeze the zone factory with what available now
   my $zone_factory = $cmdenv->{zone_factory}
     = Dibs::Zone::Factory->new($cmdenv->%*);

   my ($cnfp, $has_cloned) = ensure_configuration_file($cmdenv);
   ouch 400, 'no configuration file found' unless $cnfp->exists;
   OUTPUT("base configuration from: $cnfp");
   $cmdenv->{has_cloned} = $has_cloned;

   my $overall = add_config_file($cmdenv, $cnfp);
   $overall->{zone_factory} = $zone_factory;

   # last touch to the logger if needed
   set_logger($overall->{logger}->@*) if $overall->{logger};

   my $epoch = time();
   my $date  = strftime '%Y%m%d', gmtime $epoch;
   my $time  = strftime '%H%M%S', gmtime $epoch;
   $overall->{run_variables} = {
      DIBS_DATE  => $date,
      DIBS_EPOCH => $epoch,
      DIBS_ID    => "$date-$time-$$",
      DIBS_TIME  => $time,
   };

   # clone if necessary and not already done
   #origin_onto_src($overall) if defined($overall->{origin}) && !$cloned;

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
   $dibs->append_envile($run_variables);
   my $run_tag = $run_variables->{DIBS_ID};
   my $name = $dibs->name;

   my %args = (
      env_carriers => [$dibs],
      project_dir  => $dibs->project_dir,
      zone_factory => $dibs->zone_factory,
      run_tag => $run_tag,
      to => "$name:$run_tag",
      verbose => $config->{verbose},
   );

   # add a "cloner" if there's an origin and not cloned already
   $args{cloner} = sub {
      origin_onto_src(
         {
            $config->%*,
            zone_factory => $dibs->zone_factory,
         }
      ) unless $config->{cloned}++;
   } if defined($config->{origin}) && ! $config->{cloned};

   return $dibs->sketch($config->{do})->draw(%args);
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
