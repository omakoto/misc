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

if (( $# == 0 )) ; then
  # If no arguments is provided, check the last command output and +x the last command.
  last="$(cat "$(zenlog history -n 2)")"
  last="$(perl -ne 's!^bash: (.*): Permission denied$!\1! and print $1' <<< "$last")"
  if [[ "$last" != "" ]] && [[ -f "$last" ]] ; then
    ee chmod +x "$last"
    exit 0
  fi
  exit 2
else
  target="$1"
  target="$(find_target "$target")"

  if ! [[ -f "$target" ]] ; then
    echo "Find $1 not found." 1>&2
    exit 1
  fi

  if confirm "chmod +x $target" ; then
    ee chmod +x "$target"
    exit 0
  fi
  exit 2
fi