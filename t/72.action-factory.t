use strict;
use 5.024;
use Test::More;
use Test::Exception;
use Dibs::Zone::Factory;
use Dibs::Pack::Static;
use Dibs::Pack::Factory;
use Dibs::Action::Factory;
use Dibs::Action;
use Dibs::Action::Instance;
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

throws_ok { my $f = Dibs::Action::Factory->new }
qr{missing required...}i, 'factory constructor throws without dibspacks_factory';


my @some_spice = qw< what ever you do >;
my $spice      = $some_spice[rand @some_spice];
my %args       = (
   id           => 'whatever',
   dibspack     => 'inside:mnt',
   zone_factory => $zone_factory,
   path         => 'simple-command.sh',
   args         => [@some_spice],
   env          => {THIS => $spice},
);

my $factory;
lives_ok { $factory = Dibs::Action::Factory->new(
      dibspacks_factory => $dp_factory,
      config => {
         my_target => \%args,
      },
   ) } 'constructor with all args';

my $action;
lives_ok { $action = $factory->item('my_target') } 'proxy action creation';

my ($id, $name, $cp);
lives_ok {
   $id   = $action->id;
   $name = $action->name;
   $cp   = $action->container_path;
}
'proxied methods id, name and container_path';
is $name, $id, 'name same as id by default';
is $cp, '/mnt/simple-command.sh', 'container path';

my ($ecode, $cid, $out);
lives_ok {
   my $ez = $zone_factory->item('envile');
   ($ecode, $cid, $out) = $action->run(
      keep        => 0,
      image       => 'alpine:latest',
      project_dir => $project_dir,
      volumes     => [
         [$project_dir => '/mnt' => 'ro'],
         [$ez->host_path, $ez->container_path, 'ro'],
      ],
   );
} ## end lives_ok
'proxied method run lives';
like $out, qr{
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
}mxs, 'output from run';

done_testing();
