#!/bin/bash

# Install all go commands in subdirs
# Used in both cbin/misc and cbin

set -e
. mutil.sh

cd $(dirname $0)

for d in  */01-install.sh; do
    if [[ -x "$d" ]] ; then
        ee "$d"
    fi
done
