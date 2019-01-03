use strict;
use 5.024;
use Test::More;
use Test::Exception;
use Dibs::Zone::Factory;
use Dibs::Pack;
use Dibs::Pack::Static;

my $factory = Dibs::Zone::Factory->default;
isa_ok $factory, 'Dibs::Zone::Factory';

throws_ok { my $x = Dibs::Pack->new } qr{missing required arguments...}i,
  'no Dibs::Pack without factory';

my $static_instance;
lives_ok {
   $static_instance = Dibs::Pack::Static->new(
      id       => 'whatever',
      location => {zone => $factory->item('inside'), base => 'what'},
   );
} ## end lives_ok
'creation of static instance';
isa_ok $static_instance, 'Dibs::Pack::Static';

my $pack;
lives_ok {
   $pack = Dibs::Pack->new(factory => sub { $static_instance })
}
'Dibs::Pack OK with a factory';

my ($id, $name);
lives_ok { $id   = $pack->id } q{proxied method 'id'};
lives_ok { $name = $pack->name } q{proxied method 'name'};
is $name, $id, 'name same as id by default';

my $location;
lives_ok { $location = $pack->location } q{proxied method 'location'};
isa_ok $location, 'Dibs::Location';
is $location->host_path, undef, 'path not in host';
is $location->container_path, '/what', 'path in container';

lives_ok { $location = $pack->location($factory->items) }
q{location lives with all zones};

lives_ok {
   $location = $pack->location($factory->items('dibspacks_container'))
}
q{location lives with the right zones too};

throws_ok { my $l = $pack->location($factory->items('dibspacks_host')) }
qr{cannot materialize in any zone of...},
  q{location throws without the right zones};

done_testing();
