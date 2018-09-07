package DibsTest;
use strict;
use 5.024;
use Exporter 'import';
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

our @EXPORT = our @EXPORT_OK = qw<
   clean_environment
   directory_guard
>;


sub clean_environment { delete @ENV{(grep {/^DIBS_/} keys %ENV)} }
sub directory_guard ($path) { return DibsTest::FreezeDir->new($path) }


package DibsTest::FreezeDir;
use strict;
use 5.024;
use Path::Tiny;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use JSON::PP qw< encode_json decode_json >;

sub new ($package, $path) {
   $path = path($path);
   $path->exists or die "no path '$path'\n";
   my $flags_file = $path->child('flags.json');
   my $flags;
   if ($flags_file->exists) {
      $flags = decode_json($flags_file->slurp_raw);
   }
   else {
      $flags = {$flags_file => 1};
      $path->visit(
         sub { $flags->{$_} = 1 },
         {recurse => 1},
      );
      my $tmp = $flags_file->sibling($flags_file->basename . '.tmp');
      $tmp->spew_raw(encode_json($flags));
      $tmp->move($flags_file);

   }
   bless {path => $path, flags => $flags}, $package;
}

sub DESTROY ($self) {
   my @deletes;
   my $flags = $self->{flags};
   $self->{path}->visit(
      sub { push @deletes, $_ unless $flags->{$_} },
      {recurse => 1},
   );
   for my $d (@deletes) {
      next unless $d->exists;
      if ($d->is_dir) {$d->remove_tree({safe => 0})}
      else            {$d->remove}
   }
}

1;
