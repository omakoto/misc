#!/bin/bash
#
# Called from command not found handler when the command
# starts with an "@".
#
# See also: bash-command-not-found

command="$1"

if [[ "$command" == "" ]] ;then
    exit 1
fi

top_dirs=("$PWD" "$HOME")
if  [[ "$ANDROID_BUILD_TOP" != "" ]] &&  [[ -d "$ANDROID_BUILD_TOP" ]] ; then
    top_dirs+=("$ANDROID_BUILD_TOP")
fi

dbg() {
    : # echo "$*" 1>&2
}

make_wild() {
    local c="$1"
    local ret=""

    for ch in $(sed -e 's/\(.\)/\1\n/g' <<<"$c") ; do
        dbg "ch: $ch"

        if [[ "$ch" == "O" ]]; then
            ret="${ret}out/soong/.intermediates/"
            continue
        fi

        ret="${ret}[${ch^^}${ch,,}]*/"
    done

    echo "$ret"
}


wild="$(make_wild "$command")"
dbg "wild: $wild"

candidates=()

col=$'\e[38;5;10m'
res=$'\e[0m'

for top in "${top_dirs[@]}"; do
    dbg "top: $top"

    cd "$top"

    for d in $(ls -d $wild 2>/dev/null); do
        candidates+=("${col}${top}/${res}${d}")
    done
done

if (( "${#candidates[@]}" == 0 )) ; then
    echo "No directory found for query: $command"
    exit 1
fi

selected="$(echo "${candidates[@]}" | tr ' ' '\n' | uniq | fzf -1 --ansi)"

dbg "sel: $selected"

if [[ "$selected" != "" ]] ; then
    schedule-cd "${selected}"
fi
