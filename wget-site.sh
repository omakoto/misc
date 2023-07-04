#!/bin/bash

set -e
. mutil.sh

url="$1"
out="$(pwd)/$(date8 -s)"

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

ee wget --recursive --no-clobber --page-requisites --html-extension --convert-links --domains "$domain" --no-parent "$url"

INFO "Page saved to $out"
