#!/bin/bash -e

set -e

. mutil.sh

geo=200x80
zoom=0.85
title=""
interval=2
command=""

watch=gaze

eval "$(getopt.pl '
  g|geo|geometry=s geo=%            # Set window size. e.g. "80x25"
  z|zoom=s         zoom=%           # Set zoom scale. e.g. "0.5"
  t|title=s        title=%          # Set window title.
  n|i|interval=i   interval=%       # Set refresh interval in seconds.
  c|command=s      command=%        # Run with bash -c
  w|use-watch      watch=watch      # Use watch instead of gaze.
' "$@")"


cmd=()
cmd+=($watch "--color" "-n" "$interval" "-x")
cmd+=("$@")

if [[ "$command" != "" ]] ; then
  cmd+=(bash -c "$command")
fi

title="${title:-$@}"

unset COLORTERM
set TERM=vt100

if isx ; then
  start-terminal -t "$title" "${cmd[@]}"
else
  ee "${cmd[@]}"
fi
