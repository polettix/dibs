#!/bin/sh
set -e

: ${DOCKER_GROUP_ID:=999}
: ${DOCKER_GROUP_NAME:="docker"}
: ${USER_ID:=1000}
: ${USER_NAME:="user"}
: ${ARCHITECTURE:="$(sed -n 's/^ID=//p' /etc/os-release)"}

main() {
   groupline="$(grep ":$DOCKER_GROUP_ID:" /etc/group)"
   if [ -n "$groupline" ] ; then
      gname="${groupline%%:*}"
      gid=''
   else
      gname="$DOCKER_GROUP_NAME"
      gid="$DOCKER_GROUP_ID"
   fi

   case "$ARCHITECTURE" in
      (alpine)
         run_alpine "$gid" "$gname" "$USER_ID" "$USER_NAME"
         ;;
      (debian|ubuntu)
         run_debian "$gid" "$gname" "$USER_ID" "$USER_NAME"
         ;;
      (*)
         printf >&2 '%s' "unhandled '$ARCHITECTURE', please patch"
         ;;
   esac
}

### Alpine Linux
run_alpine() {
   local gid="$1" gname="$2" uid="$3" uname="$4"
   [ -n "$gid" ] && addgroup -G "$gid" "$gname"
   adduser -h /app -H -D -u "$uid" "$uname"
   addgroup "$uname" "$gname"
}

### Debian, Ubuntu
run_debian() {
   local gid="$1" gname="$2" uid="$3" uname="$4"
   [ -n "$gid" ] && groupadd -g "$gid" "$gname"
   useradd -d /app -M -G "$gid" -u "$uid" "$uname"
}

main "$@"
