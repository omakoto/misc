#!/bin/bash

set -e
. mutil.sh

help() {
    cat <<'EOF'

    file-foreach.sh [OPTIONS] COMMAND [COMMAND-ARGS...] -- FILES

        COMMAND-ARGS may contain %i %o for input and output filenames.
            %o is set to "%i.out"

EOF
}

export DRY=0
export INPLACE=0
export SUFFIX=".out"

parallel=0
parallel_opts="-j 100%"

eval "$(bashgetopt -u help '
  d|DRY                   DRY=1                          # Dry run
  i|suffix                INPLACE=1; SUFFIX=.bak         # In-place edit
  p|parallel              parallel=1                     # Use GNU parallel
  o|parallel-options=s    parallel=1;parallel_opts=%     # Use GNU parallel with given options
' "$@")"

export EE="ee -2"
if (( $DRY )) ; then
    EE="$EE -d"
fi

command=()

while (( $# > 0 )); do
    if [[ "$1" == "--" ]] ; then
        break
    fi

    # Make sure it doesn't contain any whitespace.
    temp=($1)
    if [[ "${temp[0]}" != "$1" ]] ; then
        echo "Command may not contain whitespace." 1>&2
        exit 1
    fi

    command+=("$1")
    shift
done

if (( $# == 0 )) ; then
    help
    exit 1
fi

shift # Remove "--"

files=("${@}")

INFO "Command: " "${command[*]}"
INFO "Fils:" "${files[*]}"

if (( $parallel )) ; then
    echo "Running with GNU Parallel, options=$parallel_opts"
fi

# For parallel, we need to exrpot command -- so if the command contains whitespace
# it'll misbehave...
export COMMAND="${command[@]}"

doit() {
    local file="$1"

    echo "Processing $file..." 1>&2
    bak="$file$SUFFIX"
    
    in="$file"
    out="$bak"
    if (( $INPLACE )) ; then
        $EE cp -p "$file" "$bak"

        in="$bak"
        out="$file"
    fi


    c=()
    for arg in $COMMAND; do
        arg="${arg//%%/%-%-}"
        arg="${arg//%i/$in}"
        arg="${arg//%o/$out}"
        arg="${arg//%-%-/%%}"
        c+=("$arg")
    done

    $EE "${c[@]}"
}

export -f doit

export FORCE_COLOR=1

if (( $parallel )) ; then
    ee parallel --progress --eta $parallel_opts doit {} ::: "${files[@]}"
else
    for file in "${files[@]}"; do
        doit "$file"
    done
fi
