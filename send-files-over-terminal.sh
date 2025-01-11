#!/bin/bash

# Script to send files to another PC over terminal.
#
# Usage: send-files-over-terminal.sh FILE ...
#
# This script will generated a script file to create the files using shar,
# and copy it to the clipboard.

set -e

. mutil.sh

content_file=/tmp/send-files.tmp
target=("$@")

rm -f "$content_file"

cat >>"$content_file" <<'__EOF__'
which uudecode || sudo apt install -y sharutils &&
/bin/bash <<'__END_OF_SEND_FILES_SHAR__' &&
__EOF__


echo "Archiving target files..." 1>&2
ee -2 shar "${target[@]}" >>"$content_file"

cat >>"$content_file" <<'__EOF__'
__END_OF_SEND_FILES_SHAR__
echo "File(s) created successfully."
__EOF__

cb < "$content_file"

echo "Now, paste from the clipboard onto a terminal on another PC."

