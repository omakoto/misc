#!/bin/bash
#
# Called from command not found handler when the command
# starts with an "@".
#
# See also: bash-command-not-found

command="$*"

if [[ "$command" == "" ]] ;then
    exit 1
fi

dbg() {
    :
    # echo "$*" 1>&2
}

mode=0 # wild card mode -- e.g. @fb, @fbr, etc
if [[ "$command" =~ \  ]] ;then
    mode=1 # search mode
fi


col=$'\e[38;5;10m'
res=$'\e[0m'

make_wild() {
    local c="$1"
    local ret=""

    for ch in $(sed -e 's/\(.\)/\1\n/g' <<<"$c") ; do
        dbg "ch: $ch"

        if [[ "$ch" == "O" ]]; then
            ret="${ret}out/soong/.intermediates/"
            continue
        fi
        if [[ "$ch" == "-" ]]; then
            ret="${ret}**/"
            continue
        fi

        ret="${ret}[${ch^^}${ch,,}]*/"
    done

    echo "$ret"
}

mode0() {
    local top_dirs=("$PWD" "$HOME")
    if  [[ "$ANDROID_BUILD_TOP" != "" ]] && [[ -d "$ANDROID_BUILD_TOP" ]] ; then
        top_dirs+=("$ANDROID_BUILD_TOP")
    fi

    local wild="$(make_wild "$command")"
    dbg "wild: $wild"

    for top in $(echo "${top_dirs[@]}" | tr ' ' '\n' | global-unique) ; do
        dbg "top: $top"

        cd "$top"

        for d in $(ls -d $wild 2>/dev/null); do
            candidates+=("${col}${top}/${res}${d}")
        done
    done
}

make_pcre() {
    local c="$1"
    local ret="^"

    for token in $c ; do
        dbg "token: $token"

        ret="${ret}.*?/$token[^/]*?"
    done

    echo "$ret\$"
}


mode1() {
    local pcre="$(make_pcre "$command")"
    dbg "pcre: $pcre"

    local top_dirs=("$HOME/cbin")
    local d
    if  [[ "$ANDROID_BUILD_TOP" != "" ]] && [[ -d "$ANDROID_BUILD_TOP" ]] ; then
        for d in frameworks cts tools build out; do
            top_dirs+=("$ANDROID_BUILD_TOP/$d")
        done
    fi
    candidates=( $(
        ffind -d -j 32 -q "${top_dirs[@]}" \
            | grep -P -- "$pcre" \
            | global-unique \
            | sort \
    ) )
}

candidates=()

if (( $mode == 0 )) ; then
    mode0
elif (( $mode == 1 )) ; then
    mode1
    # top_dirs=("$HOME/cbin/")


    # ffind -d -q -j 32 "${top_dirs[@]}"
    # exit 99
else
    echo "unknown mode: $mode"
    exit 13
fi


if (( "${#candidates[@]}" == 0 )) ; then
    echo "No directory found for query: $command"
    exit 1
fi

selected="$(echo "${candidates[@]}" | tr ' ' '\n' | uniq | fzf -1 --ansi)"

dbg "sel: $selected"

if [[ "$selected" != "" ]] ; then
    schedule-cd "${selected}"
fi
