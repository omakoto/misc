#!/bin/bash

# Mic mute indicator on tasktray.

set -e
. mutil.sh

MIXERS=(Dmic0 Capture)

SCRIPT="${0##*/}"
SCRIPT_DIR="${0%/*}"
cd "$SCRIPT_DIR"

# Make sure there's only one instance running.
if pidof -o %PPID -x $0 >/dev/null; then
  echo "$SCRIPT already started."
  exit 1
fi

muted_icon=microphone-muted2.png
unmuted_icon=microphone.png

is_muted() {
  muted=0
  for name in $MIXERS ; do
    if amixer sget $name 2>&1 | grep -q 'Front.*\[off\]' ; then
      muted=1
      break
    fi
  done
  return $(( $muted == 0 ))
}

#is_muted && echo 'muted'
stdbuf -oL amixer sevents | stdbuf -oL sed -ne '2,/^Ready to listen/d; /^event/p' | while read n ; do
  icon=$unmuted_icon
  if is_muted ; then
    icon=$muted_icon
  fi
  echo "icon:$icon"
done | {
  yad --notification --no-middle --image $unmuted_icon --text 'Mic Mute Indicator' --menu 'Quit!quit' --command '' --listen
  pkill -P $$
}