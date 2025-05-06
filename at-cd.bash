#!/bin/bash
#
# Called from command not found handler when the command
# starts with an "@".
#
# See also: bash-command-not-found

if (( $# == 0 )) ;then
    exit 1
fi

export LC_ALL=C

dbg() {
    :
    # echo "$*" 1>&2
}

# Default wild card mode -- e.g. @fb, @fbr, etc
mode=0

# If the query contains a space, use mode1.
if [[ "$*" =~ \  ]] ; then
    mode=1
fi

set -- $*

use_pwd=0

# If the first token is ".", then use mode1 and starts from $PWD.
if [[ "$1" == "." ]] ;then
    use_pwd=1
    mode=1
    shift
fi

command="$*"

dbg "query: mode=$mode: $command" 1>&2

# ---------------------

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

# Example "@ o f b r" should match out/ .../ frameworks/base/ravenwood

make_re() {
    local c="$1"
    local ret="^"

    for token in $c ; do
        dbg "token: $token"

        ret="${ret}.*?/\.?$token[^/]*?"
    done

    echo "$ret\$"
}

ffind_opts='-i x86_64.* -i android_common -i android_x86.* -i android_vendor_x86.*'

mode1() {

    local d
    local top_dirs
    if (( $use_pwd )) ; then
        top_dirs+=("$PWD")
    else
        top_dirs+=("$HOME/cbin")
        if  [[ "$ANDROID_BUILD_TOP" != "" ]] && [[ -d "$ANDROID_BUILD_TOP" ]] ; then
            for d in frameworks cts tools build out; do
                top_dirs+=("$ANDROID_BUILD_TOP/$d")
            done
        fi
    fi

    local re="$(make_re "$command")"
    dbg "re: $re"

    candidates=( $(
        ee -2 ffind $ffind_opts -d -j 32 -q "${top_dirs[@]}" \
            | grep -Ei -- "$re" \
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
