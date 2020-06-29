#!/bin/bash

set -e
. mutil.sh

dir="$1"
if [[ "$dir" == "" ]] ; then
  cat <<'EOF'

  md: mkdir -p && cd

  usage: md PATH

EOF
  exit 1
fi

ee mkdir -p "$dir" && schedule-cd "$dir"
