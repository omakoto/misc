#!/bin/bash

# Open the first URL in the previous log in the browser.

set -e

. mutil.sh

for n in 1 2 3 4 5; do
  log=$(zenlog history -n $n)
  if ! [[ -f $log ]] ; then
    exit 1
  fi

  url=$(perl -ne '/Run hook/ and next; m!((https?|file)\:\S+)! and print "$1\n" and exit 0' "$log")

  if [[ -n "$url" ]] ; then
    echo "Opening $url ..." 1>&2
    ee ${BROWSER:-google-chrome} "$url"
    exit 0
  fi
done
exit 1
