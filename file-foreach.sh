#!/bin/bash

set -e
. mutil.sh

help() {
    cat <<'EOF'

  file-foreach.sh [OPTIONS] FILES -- COMMAND [COMMAND-ARGS...]

    COMMAND-ARGS may contain %i %o for input and output filenames.
       %o is set to "%i.out"

    -d: dry run
    -i: In-place edit
EOF
}

dry=0
inplace=0
suffix=".out"

eval "$(bashgetopt -u usage '
  d|dry           dry=1                    # Dry run
  i|suffix        inplace=1; suffix=.bak   # Inplace 
' "$@")"

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
    bak="$file$suffix"
    
    in="$file"
    out="$bak"
    if (( $inplace )) ; then
        $EE cp -p "$file" "$bak"

        in="$bak"
        out="$file"
    fi


    c=()
    for arg in "${command[@]}"; do
        arg="${arg//%%/%-%-}"
        arg="${arg//%i/$in}"
        arg="${arg//%o/$out}"
        arg="${arg//%-%-/%%}"
        c+=("$arg")
    done

    $EE "${c[@]}"

done
