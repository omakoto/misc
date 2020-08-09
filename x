#!/bin/bash

set -e
. mutil.sh

find_target() {
  local t="$1"
  if [[ -f "$t" ]] ; then
    echo "$t"
    return 0
  fi
  if [[ "$t" =~ ^/ ]] ; then
    echo $t
    return 0
  fi
  for p in $(tr ':' ' ' <<< "$PATH") ; do
    if [[ -f "$p/$t" ]] ; then
      echo "$p/$t"
      return 0
    fi
  done < <(echo "$PATH")
  return 1
}

target="$1"
target="$(find_target "$target")"

if ! [[ -f "$target" ]] ; then
  echo "Find $1 not found." 1>&2
  exit 1
fi

if confirm "chmod +x $target" ; then
  chmod +x "$target"
  exit 0
fi
exit 2