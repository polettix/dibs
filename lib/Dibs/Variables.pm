package Dibs::Variables;
use 5.024;
use Ouch ':trytiny_var';
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub dvf_array_flatten ($o, $x)  { return $x->@*            }
sub dvf_array_wrap ($o, @x)     { return [@x]              }
sub dvf_env ($o, @x)            { return @ENV{@x}          }
sub dvf_identity ($o, @x)       { return @x                }
sub dvf_join ($o, $sep, @items) { return join $sep, @items }
sub dvf_set_runv ($o, $k, $v)   { $o->{run_variables}{$k} = $v }
sub dvf_runv ($o, $key)         { return $o->{run_variables}{$key} }

1;
__END__


