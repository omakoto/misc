#!/bin/bash
#
# Called from command not found handler when the command
# starts with an "@".
#
# See also: bash-command-not-found

set -e

. mutil.sh

query="$*"
# query="$(sed -e 's/^  *//' <<< "$query")" # Strip leading spaces

if [[ "$query" == "" ]] ;then
    exit 1
fi

export LC_ALL=C

dbg() {
    if (( $ATCD_DEBUG )) ; then
        echo "DEBUG: $*" 1>&2
    fi
}

# Default wild card mode -- e.g. @fb, @fbr, etc
mode=0

# If the query contains a space or a period, use mode1.
if [[ "$query" =~ [\ -]  ]] ; then
    mode=1
fi

use_pwd=0

# If the query starts with a  ".", then use mode1 and starts from $PWD.
if [[ "$query" =~ ^\. ]] ;then
    use_pwd=1
    mode=1
    query="${query:1}"
fi


# ---------------------

found() {
    (( ${#candidates[@]} > 0 ))
    return $?
}

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
    local query="$1"
    shift

    echo "# mode 0: ${query%Q}" 1>&2

    local top_dirs=("$PWD" "$HOME")
    if  [[ "$ANDROID_BUILD_TOP" != "" ]] && [[ -d "$ANDROID_BUILD_TOP" ]] ; then
        top_dirs+=("$ANDROID_BUILD_TOP")
    fi

    local wild="$(make_wild "$query")"
    dbg "wild: $wild"

    for top in $(echo "${top_dirs[@]}" | tr ' ' '\n' | global-unique) ; do
        dbg "top: $top"

        cd "$top"

        for d in $(ls -d $wild 2>/dev/null); do
            candidates+=("${col}${top}/${res}${d}")
        done
    done

    if ! found ; then
        mode1 "$query"
    fi
}

# Example "@ o f b r" should match out/ .../ frameworks/base/ravenwood

make_re() {
    local q="$1"
    local ret=""

    echo "# mode 1: ${query%Q}" 1>&2

    local tokens="$(perl -e 'print join(" ", split(/(?: \s+ | \b )/x, $ARGV[0]))' -- "$q")"

    INFO "tokens: $tokens" 1>&2

    for token in $tokens ; do
        dbg "token: $token"

        if [[ "$token" == "-" ]] ; then
            ret="${ret}.*?"
            continue
        fi
        ret="${ret}/[\.]?$token[^/]*?"
    done

    echo "$ret"
}

ffind_max_depth=8
ffind_opts='-i node_modules -i x86_64.* -i android_common -i android_x86.* -i android_vendor_x86.* -i res'" -m $ffind_max_depth"

mode1() {
    local query="$1"
    local d
    local top_dirs
    local prefixes

    if (( $use_pwd )) ; then
        top_dirs=("$PWD")
        prefixes=("$PWD")
    else
        top_dirs+=("$HOME/cbin")
        prefixes+=("$HOME")
        if  [[ "$ANDROID_BUILD_TOP" != "" ]] && [[ -d "$ANDROID_BUILD_TOP" ]] ; then
            prefixes+=("$ANDROID_BUILD_TOP")
            top_dirs+=( "$ANDROID_BUILD_TOP" )

            local i
            for i in $(cd "$ANDROID_BUILD_TOP" && echo dev* pdk* 00* vendor hardware dalvik bootable kernel prebuilts sdk prebuilts external) ; do
                ffind_opts="$ffind_opts -x $ANDROID_BUILD_TOP/$i"
                ffind_opts="$ffind_opts -x $ANDROID_BUILD_TOP/out/soong/.intermediates/$i"
            done
            ffind_opts="$ffind_opts -x $OUT"
        fi
    fi

    local re=""
    for p in "${prefixes[@]}"; do
        re="${re}|${p}"
    done
    re="^(${re:1})" # Strip the first `|`
    local prefix_re="$re"
    re="${re}$(make_re "$query")"
    re="${re}\$"
    
    INFO "prefix: $prefix_re"
    INFO "re: $re"

    # exit 99

    candidates=( $(
        ee -2 ffind $ffind_opts -d -j 32 -q -- "${top_dirs[@]}" \
            | grep -Ei -- "$re" \
            | sort -u \
            | hl "$prefix_re" '@yellow/black@white/black' \
    ) )

    # If no candidates found, fallback.
    if ! found && ! [[ $query =~ ^- ]]  ; then
        mode1 -"$query"
    fi
}

candidates=()

if (( $mode == 0 )) ; then
    mode0 "$query"
elif (( $mode == 1 )) ; then
    mode1 "$query"
else
    echo "unknown mode: $mode"
    exit 13
fi


if (( "${#candidates[@]}" == 0 )) ; then
    echo "No directory found for query: $query"
    exit 1
fi

selected="$(echo "${candidates[@]}" | tr -s '/' '/' | tr ' ' '\n' | uniq | fzf -1 --ansi)"

dbg "sel: $selected"

if [[ "$selected" != "" ]] ; then
    schedule-cd "${selected}"
fi
