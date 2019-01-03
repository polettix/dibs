use strict;
use 5.024;
use Test::More;
use Test::Exception;
use Dibs::Zone::Factory;
use Dibs::Pack::Static;
use Dibs::Action;
use Dibs::Action::Instance;
use Path::Tiny 'path';
use lib path(__FILE__)->parent->stringify;
use DibsTest;

my $project_dir = path(__FILE__ . '.d')->absolute;
$project_dir->mkpath unless $project_dir->exists;
my $guard = directory_guard($project_dir);

my $factory = Dibs::Zone::Factory->default($project_dir);
isa_ok $factory, 'Dibs::Zone::Factory';

my $dp = Dibs::Pack::Static->new(
   id       => 'whatever',
   location => {zone => $factory->item('inside'), base => 'mnt'},
);
can_ok $dp, qw< location env envile >;

throws_ok { my $a = Dibs::Action->new } qr{missing required...}i,
  'factory necessary for action';

my @some_spice = qw< what ever you do >;
my $spice = $some_spice[rand @some_spice];
my %args = (
   id           => 'whatever',
   dibspack     => $dp,
   zone_factory => $factory,
   path => 'simple-command.sh',
   args => [@some_spice],
   env => {THIS => $spice},
);

for my $missing (qw< dibspack id zone_factory >) {
   my %margs = %args;
   delete $margs{$missing};
   throws_ok { my $fake = Dibs::Action::Instance->new(%margs) }
   qr{missing.*\Q$missing\E...}i, "$missing necessary for action instance";
} ## end for my $missing (qw< dibspack id zone_factory >)

my $action_instance;
lives_ok { $action_instance = Dibs::Action::Instance->new(%args) }
'instance creation';

my $action;
lives_ok {
   $action = Dibs::Action->new(factory => sub { $action_instance })
}
'proxy action creation';

my ($id, $name, $cp);
lives_ok {
   $id = $action->id;
   $name = $action->name;
   $cp = $action->container_path;
} 'proxied methods id, name and container_path';
is $name, $id, 'name same as id by default';
is $cp, '/mnt/simple-command.sh', 'container path';

my ($ecode, $cid, $out);
lives_ok {
   my $ez = $factory->item('envile');
   ($ecode, $cid, $out) = $action->run(
      keep => 0,
      image => 'alpine:latest',
      project_dir => $project_dir,
      volumes => [
         [$project_dir => '/mnt' => 'ro'],
         [$ez->host_path, $ez->container_path, 'ro'],
      ],
   );
} 'proxied method run lives';
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
