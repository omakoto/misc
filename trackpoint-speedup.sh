#!/bin/bash

set -e
. mutil.sh
id=$(xinput list --id-only "TPPS/2 Elan TrackPoint" 2>/dev/null || true)
if [[ "$id" == "" ]]; then
    echo "Trackpoint not found." 1>&2
    exit 0
fi

prop=$(xinput list-props $id  | perl -ne '/libinput Accel Speed \((\d+)/ and print $1')

ee xinput set-prop $id $prop 1
echo '  Updated trackpoint speed successfully.'
