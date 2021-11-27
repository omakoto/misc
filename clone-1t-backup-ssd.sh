#!/bin/bash

set -e
. mutil.sh

if ! [[ -e /dev/mapper/luks-2ded3f73-866c-496e-9466-42ec30d400ad ]] || ! [[ -e /dev/mapper/luks-7db17b5b-fef7-483a-b83c-62d8afe0f684 ]] ; then
    echo 'Target or source disk not found. Make sure to decrypt them first.' 1>&2
    exit 1
fi

exit 0


ee sudo partclone.ext4 -d -b -s /dev/mapper/luks-2ded3f73-866c-496e-9466-42ec30d400ad -o /dev/mapper/luks-7db17b5b-fef7-483a-b83c-62d8afe0f684
