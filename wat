#!/bin/bash -e

set -e

. mutil.sh

geo=200x80
zoom=0.85
title=""
interval=2

eval "$(getopt.pl '
  g|geo|geometry=s geo=%            # Set window size. e.g. "80x25"
  z|zoom=s         zoom=%           # Set zoom scale. e.g. "0.5"
  t|title=s        title=%          # Set window title.
  n|i|interval=i   interval=%       # Set refresh interval in seconds.
' "$@")"


cmd=()
cmd+=("watch" "-n" "$interval" "-x" "-p")
cmd+=("$@")

title="${title:-$@}"

if isx ; then
  start-terminal "${cmd[@]}"
else
  ee "${cmd[@]}"
fi
