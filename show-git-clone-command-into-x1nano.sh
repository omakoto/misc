#!/bin/bash

set -e
. mutil.sh

SCRIPT="${0##*/}"
SCRIPT_DIR="${0%/*}"

target="$1"

if ! [[ -d "$target" ]] || ! [[ -d "$target.git" ]]; then
    echo "Usage: $SCRIPT GIT-TOP-DIR"
fi

fullpath="$(readlink -e "$target")"

cat <<EOF

# Use this command to clone the git directory.
git clone ssh://omakoto@192.168.86.240:$fullpath/.git

# Also use the following commands as needed.

# To add ssh-add to ~/.profile, use it.
add-ssh-init-to-profile.sh # Copy a script to add ssh-add to ~/.profile

# To copy ssh identity files to a remote PC, use it.
send-ssh-identitiy-over-terminal.sh

EOF
