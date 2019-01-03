use strict;
use 5.024;
use Test::More;
use Dibs::Zone;

my $zone = Dibs::Zone->new(
   name           => 'whatever',
   host_base      => 'some/whatever',
   container_base => '/tmp/whatever',
);

isa_ok $zone, 'Dibs::Zone';
ok $zone,     'boolean overloading';
is "$zone", 'whatever', 'string overloading';

my %hash = ($zone => 'hey');
is_deeply \%hash, {whatever => 'hey'}, 'as key in hash';

delete $hash{$zone};
is_deeply \%hash, {}, 'as key in hash (delete)';

$hash{$zone} = 'you';
is_deeply \%hash, {whatever => 'you'}, 'as key in hash ($h{key})';
is $hash{$zone}, 'you', 'direct access as key in hash';

is $zone->host_path,      'some/whatever', 'host path';
is $zone->container_path, '/tmp/whatever', 'container path';
is $zone->host_path(qw< to else >), 'some/whatever/to/else',
  'host subpath';
is $zone->container_path(qw< gal ok >), '/tmp/whatever/gal/ok',
  'container subpath';
isa_ok $zone->host_path, 'Path::Tiny', 'host path returns a path';
isa_ok $zone->container_path, 'Path::Tiny',
  'container path returns a path';

$zone = Dibs::Zone->new(name => 'whatever', host_path => '.');
is $zone->container_path, undef, 'undef remains undef';
is $zone->container_path(qw< what ever >), undef, 'undef remains undef';

done_testing();
