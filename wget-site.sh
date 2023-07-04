#!/bin/bash

set -e
. mutil.sh

url="$1"
out="$(pwd)/$(date8 -s)"

UA="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"

usage() {
    cat <<'EOF'

  wget-site.sh URL

EOF
}

if [[ -z "$url" ]] ; then
    usage
    exit 1
fi

domain="$(perl -e '$ARGV[0] =~ m!//(.*?)/! and print $1' $url)"

if [[ -z "$domain" ]] ; then
    ERROR 'Unable to extract the domain name'
    usage
    exit 1
fi

INFO "URL:" "$url"
INFO "Domain:" "$domain"

ee mkdir -p "$out"
ee cd "$out"

ee wget --recursive --span-hosts --no-clobber --page-requisites --html-extension --convert-links --domains "$domain" --user-agent="$UA" --no-parent "$url"

INFO "Page saved to $out"
