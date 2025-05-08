#!/bin/bash

config="$(cat <<'EOF'
    3s  x10     2
    3s     x20  2
    5s  x10     3
    5s     x20  3
    30s x1
EOF
)"

sel=$(echo "$config" | fzf | tr 'x' ' ')

if [[ "$sel" == "" ]]; then
    exit 1
fi

ee timer -2 $sel
