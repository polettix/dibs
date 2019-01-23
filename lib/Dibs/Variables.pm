package Dibs::Variables;
use 5.024;
use POSIX 'strftime';
use Ouch ':trytiny_var';
use English qw< -no_match_vars >;
use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

sub dvf_array_flatten ($o, $x)  { return $x->@*                       }
sub dvf_array_wrap ($o, @x)     { return [@x]                         }
sub dvf_dibs_id ($o)            { return $o->{run_variables}{DIBS_ID} }
sub dvf_env ($o, @x)            { return @ENV{@x}                     }
sub dvf_get_runvar ($o, $key)   { return $o->{run_variables}{$key}    }
sub dvf_get_var ($o, $key)      { return $o->{named_variables}{$key}  }
sub dvf_join ($o, $sep, @x)     { return join $sep, @x                }
sub dvf_passthrough ($o, @x)    { return @x                           }
sub dvf_set_runvar ($o, $k, $v) { $o->{run_variables}{$k} = $v        }
sub dvf_set_var ($o, $k, $v)    { $o->{named_variables}{$k} = $v      }
sub dvf_sprintf ($o, $fmt, @x)  { return sprintf $fmt, @x             }

# time-specific functions
sub dvf_dibs_date ($o)  { return $o->{run_variables}{DIBS_DATE}          }
sub dvf_dibs_epoch ($o) { return $o->{run_variables}{DIBS_EPOCH}         }
sub dvf_dibs_time ($o)  { return $o->{run_variables}{DIBS_TIME}          }
sub dvf_epoch ($o)      { return time()                                  }
sub dvf_gmtime ($o, $e = undef)    { gmtime($e // dfv_dibs_epoch($o))    }
sub dvf_localtime ($o, $e = undef) { localtime($e // dfv_dibs_epoch($o)) }
sub dvf_strftime ($o, $format, @rest) {
   @rest = dfv_gmtime($o) unless @rest;
   return strftime $format, @rest;
}

1;
__END__


