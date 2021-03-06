use strict;
use 5.024;
use Test::More;
use Test::Exception;
use Dibs::Zone::Factory;

my $factory;
lives_ok { $factory = Dibs::Zone::Factory->default } 'default factory';
isa_ok $factory, 'Dibs::Zone::Factory';
can_ok $factory, qw< item items >;

################################## NOTE ###################################
# If any of the tests within this note fail, it might actually be something
# related to Dibs::Configuration (where DEFAULTS is defined)

my $src_zone;
lives_ok { $src_zone = $factory->item('src') } 'src zone exists';
isa_ok $src_zone, 'Dibs::Zone';

throws_ok { my $x = $factory->item('I am not here!') } qr{no zone...},
  'missing zone throws';

my $host_only_zone;
lives_ok { $host_only_zone = $factory->item('hostpack') }
'host-only zone';
isa_ok $host_only_zone, 'Dibs::Zone';
is $host_only_zone->container_base, undef, 'no container path inside';

my $container_only_zone;
lives_ok { $container_only_zone = $factory->item('inside') }
'container-only zone';
isa_ok $container_only_zone, 'Dibs::Zone';
is $container_only_zone->host_base, undef, 'no host path inside';

my @list;
lives_ok { @list = $factory->items('volumes') }
q{list of zones in assemble 'volumes'};
is scalar(@list), 6, q{'volumes' contains six items};
isa_ok $list[0], 'Dibs::Zone';
is_deeply [map { "$_" } @list], [qw< src cache envile env autopack pack >],
  q{items in 'volumes'};

my @all;
lives_ok { @all = $factory->items } 'getting all items';
ok scalar(@all) >= 3, 'several items inside';
isa_ok $all[0], 'Dibs::Zone';

throws_ok {
   my @w = $factory->items('I am not here as well!');
}
qr{invalid filter...}, 'inexistent assemble throws';

done_testing();
