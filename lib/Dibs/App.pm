package Dibs::App;
use 5.024;
use Try::Catch;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Ouch qw< :trytiny_var >;
use Path::Tiny qw< path cwd >;
use POSIX 'strftime';

use Exporter 'import';
our @EXPORT_OK = qw< main create_from_cmdline >;

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

   # start looking for the configuration file, refer it to the project dir
   # if relative, otherwise leave it as is
   my $cnfp = path($cmdenv->{config_file});
   $log->info("cnfp: $cnfp");

   # development mode is a bit special in that dibs.yml might be *inside*
   # the repository itself and the origin needs to be cloned beforehand
   my $is_alien       = $cmdenv->{alien};
   my $is_development = $cmdenv->{development};
   if ((!$cnfp->exists) && ($is_alien || $is_development)) {
      my $src_dir = origin_onto_src($cmdenv);

      # there's no last chance, so config_file is set
      $cnfp = $src_dir->child($cmdenv->{config_file});
   } ## end if ((!$cnfp->exists) &&...)

   ouch 400, 'no configuration file found' unless $cnfp->exists;

   my $overall = add_config_file($cmdenv, $cnfp);

   # restore SRC if we just cloned it, we cannot allow overriding it
   # at this point!
   $overall->{zone_specs_for}{&SRC} = $overall->{has_cloned}
     if $overall->{has_cloned};

   # last touch to the logger if needed
   set_logger($overall->{logger}->@*) if $overall->{logger};

   $overall->{run_variables} = {
      DIBS_ID => strftime("%Y%m%d-%H%M%S-$$", gmtime),
   };

   return $overall;
} ## end sub initialize (@as)

sub main (@as) {
   try {
      my $config = initialize(@as);
      my $dibs   = Dibs->new($config);
      $dibs->append_envile($config->{run_variables});
      my $album  = $dibs->album(
         {
            id       => 'main',
            sections => $config->{draw},
         }
      );
      $album->draw(
         env_carriers => [$dibs],
         run_tag => $config->{run_variables}{DIBS_ID},
      );
      return 0;
   } ## end try
   catch {
      $log->fatal(ref $_ ? $_->trace : $_);
      return 1;
   };
} ## end sub main (@as)

sub origin_onto_src ($config) {
   my $origin = $config->{origin} // '';
   $origin = cwd() . $origin
     if ($origin eq '') || ($origin =~ m{\A\#.+}mxs);

   # save $src_zone in $config->{has_cloned} so that we will not clone
   # again later AND src will not be overridden
   my $src_zone = $config->{has_cloned} =
     Dibs::Zone::Factory->new($config->%*)->zone_for(SRC);
   my $src_dir = $src_zone->host_base;
   my $dirty   = $config->{dirty} // undef;

   ARROW_OUTPUT('=', "early clone of origin $origin");
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
