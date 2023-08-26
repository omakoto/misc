#!/bin/bash

set -e
. mutil.sh

help() {
    cat <<'EOF'

  file-inplace-apply.sh [OPTIONS] FILES -- COMMAND [COMMAND-ARGS...]

    COMMAND-ARGS may contain: %i %o for input and output filenames.

    -d: dry run
    -i SUFFIX: back up file suffix
EOF
}

dry=0
suffix=".bak"

eval "$(bashgetopt -u usage '
  d|dry           dry=1            # Dry run
  i|suffix=s      suffix=%         # Backup suffix
' "$@")"

if [[ "$suffix" == "" ]] ; then
    help
    exit 1
fi

EE="ee -2"
if (( $dry )) ; then
    EE="$EE -d"
fi

files=()

while (( $# > 0 )); do
    if [[ "$1" == "--" ]] ; then
        break
    fi
    files+=("$1")
    shift
done

if [[ "$1" != -- ]] ; then
    help
    exit 1
fi

shift # Remove "--"

command=("${@}")

INFO "Command: " "${command[*]}"
INFO "Fils:" "${files[*]}"

for file in "${files[@]}"; do
    to="$file$suffix"
    $EE cp -p "$file" "$to"

    c=()
    for arg in "${command[@]}"; do
        arg="${arg//%%/%-%-}"
        arg="${arg//%i/$to}"
        arg="${arg//%o/$i}"
        arg="${arg//%-%-/%%}"
        c+=("$arg")
    done

    $EE echo "${c[@]}"

done
