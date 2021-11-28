#!/bin/bash

set -e
. mutil.sh

if ! [[ -e /dev/mapper/luks-f304748c-610b-426e-ab51-b5fcbd4d337f ]] || ! [[ -e /dev/mapper/luks-157c47a2-4291-4a68-a76a-83cf46e76cbf ]] ; then
    echo 'Target or source disk not found. Make sure to decrypt them first.' 1>&2
    exit 1
fi

ee sudo partclone.ext4 -d -b -s /dev/mapper/luks-f304748c-610b-426e-ab51-b5fcbd4d337f -o /dev/mapper/luks-157c47a2-4291-4a68-a76a-83cf46e76cbf
