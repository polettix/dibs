#!/bin/sh
md="$(cd "$(dirname "$0")"; pwd)"
[ -e './export-enviles.sh' ] && . ./export-enviles.sh
all_of_it="$(
   printf '%s\n' "received: $*"
   printf '%s\n' 'env:'
   env
   printf '%s\n' "I live in $md"
   ls -l "$md"
   printf '%s\n' 'end of file list'
   printf '%s\n' "currently in $PWD"
   ls -l
   printf '%s\n' 'end of file list'
)"

printf '%s\n%s' 'this on standard output' "$all_of_it"
printf '%s\n%s' 'this on standard error'  "$all_of_it" >&2
