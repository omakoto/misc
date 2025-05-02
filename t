#!/bin/bash

config="$(cat <<'EOF'
    3s  x10     2
    3s     x20  2
    5s  x10
    5s     x20
    30s x10
EOF
)"

sel=$(echo "$config" | fzf | tr 'x' ' ')

if [[ "$sel" == "" ]]; then
    exit 1
fi

ee timer -2 $sel 3
