use strict;
use 5.024;
use Test::More;
use Test::Exception;
use Dibs::Zone::Factory;
use Dibs::Pack::Factory;
use Dibs::Action::Factory;
use Dibs::Process::Factory;
use Path::Tiny 'path';
use lib path(__FILE__)->parent->stringify;
use DibsTest;

my $project_dir = path(__FILE__ . '.d')->absolute;
$project_dir->mkpath unless $project_dir->exists;
my $guard = directory_guard($project_dir);

my $zone_factory = Dibs::Zone::Factory->default($project_dir);
isa_ok $zone_factory, 'Dibs::Zone::Factory';

my $dp_factory = Dibs::Pack::Factory->new(zone_factory => $zone_factory);
isa_ok $dp_factory, 'Dibs::Pack::Factory';

my @some_spice = qw< what ever you do >;
my $spice      = $some_spice[rand @some_spice];

my $a_factory;
lives_ok {
   $a_factory = Dibs::Action::Factory->new(
      dibspacks_factory => $dp_factory,
      config            => {
         my_target => {
            id           => 'action whatever',
            dibspack     => 'inside:mnt',
            zone_factory => $zone_factory,
            path         => 'simple-command.sh',
            args         => [@some_spice],
            envile       => {THIS => $spice},
         },
      },
     )
} ## end lives_ok
'constructor with all args';

throws_ok { my $x = Dibs::Process::Factory->new } qr{missing required...}i,
  'process constructor needs arguments';

my %args = (
);

my $process_factory;
lives_ok {
   $process_factory = Dibs::Process::Factory->new(
      actions_factory => $a_factory,
      config => {
         'work-please' => {
            actions_factory => $a_factory,
            id => 'whatever',
            from => 'alpine:latest',
            actions => [
               'my_target', # by name, known by the factory
               {            # direct specification
                  id => 'other whatever',
                  dibspack => 'inside:/mnt/simple-command.sh',
                  zone_factory => $zone_factory,
                  args => [reverse @some_spice],
                  envile => {THAT => $spice},
               },
            ],
            env => [ {WHAT => 'ever'} ],
         },
      },
   );
}
'process instance constructor OK with all arguments';

my $process;
lives_ok {
   $process = $process_factory->item('work-please');
}
'process proxy fetching from factory';

my ($id, $name);
lives_ok {
   $id = $process->id;
   $name = $process->name;
} 'methods id, name from proxy object (process)';
is $name, $id, 'name defaults to id';

my $outcome;
lives_ok {
   my $ez = $zone_factory->item('envile');
   $outcome = $process->run(
      working_image_name => path(__FILE__)->basename,
      project_dir => $project_dir,
      volumes     => [
         [$project_dir => '/mnt' => 'ro'],
         [$ez->host_path, $ez->container_path, 'ro'],
      ],
   );
} ## end lives_ok
'proxied method run lives';

is scalar(@{$outcome->{outputs}}), 2, 'output from 2 actions';
my ($out1, $out2) = @{$outcome->{outputs}};
like $out1, qr{
   \A
     ^this\ on\ standard\ output$ \s*
     ^received:\ what\ ever\ you\ do$ \s*
     ^env:$ \s*
     .*
     ^THIS=\Q$spice\E$ \s*
     .*
     ^I\ live\ in\ /mnt$ \s*
     .*
     ^end\ of\ file\ list$ \s*
     ^currently\ in\ \S*envile$
     .*
     ^end\ of\ file\ list$
   \z
}mxs, 'output from running first action';

unlike $out1, qr{^THAT=}mxs, 'no cross-pollination of envile';

like $out2, qr{
   \A
     ^this\ on\ standard\ output$ \s*
     ^received:\ do\ you\ ever\ what$ \s*
     ^env:$ \s*
     .*
     ^THAT=\Q$spice\E$ \s*
     .*
     ^I\ live\ in\ /mnt$ \s*
     .*
     ^end\ of\ file\ list$ \s*
     ^currently\ in\ \S*envile$
     .*
     ^end\ of\ file\ list$
   \z
}mxs, 'output from running first action';

unlike $out2, qr{^THIS=}mxs, 'no cross-pollination of envile';

like $_, qr{^WHAT=ever$}mxs, 'process-level environment variable',
   for ($out1, $out2);

done_testing();
