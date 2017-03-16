#!/bin/bash

# Open the first URL in the previous log in the browser.

set -e

. mutil.sh

url=$(perl -ne '/Run hook/ and next; m!((https?|file)\:\S+)! and print "$1\n" and exit 0' $(zenlog_last_log "$@"))

if [[ -z "$url" ]] ; then
  echo "$0: URL not found in the previous command output" 1>&2
  exit 1
fi

echo "Opening $url ..." 1>&2
ee ${BROWSER:-google-chrome} "$url"
