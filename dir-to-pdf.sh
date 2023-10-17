#!/bin/bash

set -e
shopt -s nullglob

. mutil.sh

ok=0

for dir in "${@}" ; do
    dir=$(echo "$dir" | sed -e 's!//*$!!')
    echo "# Processing $dir ..."
    files=( $(echo "$dir"/*.{jpg,jpeg,png} | sort -V) )
    for file in "${files[@]}"; do
        echo "  found $file"
    done
    if (( "${#files[@]}" == 0 )) ; then
        echo "No image found in directory \"$dir\"" 1>&2
        continue
    fi
    ee img2pdf --output "${dir}.pdf" "${files[@]}"
    ok=1
done

if (( $ok )) ; then
    exit 0
else
    exit 1
fi
