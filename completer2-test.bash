#!/bin/bash

. testutil.bash

# Init files -----------------------------------------------
export MOCK_HOME=/tmp/home
export TAB="$(echo -e "\t")"

export SHELL=/bin/bash

umask 0077

unset PS0
unset PS1
unset PS2
unset PS3
unset PS4
unset PROMPT_COMMAND

cd "${0%/*}"
medir="$(pwd)"

verbose=0
if [[ "$1" == "-v" ]] ; then
  verbose=1
  shift
fi

make_dir() {
  local mode=$1
  local name=$2
  local path="$MOCK_HOME/$name"
  mkdir -p "$path"
  chmod $mode "$path"
}

make_file() {
  local mode=$1
  local name=$2
  local path="$MOCK_HOME/$name"
  mkdir -p "$(dirname "$path")"
  touch "$path"
  chmod $mode "$path"
}

rm -fr $MOCK_HOME

make_file 400 .aa1
make_file 400 .aa2
make_file 400 .bb1
make_file 400 aa1
make_file 400 aa2
make_file 400 bb1
make_dir  700 ddd1/aaaa
make_dir  700 ddd1/AAAA
make_dir  700 ddd1/aabb
make_file 500 ddd1/bbbb/fff1.jpg
make_file 500 ddd1/bbbb/FFF2.jpg
make_file 500 ddd1/bbbb/FFF3.png
make_file 500 ddd1/bbbb/aaa.jpg
make_dir  700 ddd2/aaa/bbb
make_file 700 ddd2/aaa/ccc/file1
make_file 700 ddd2/aaa/ccc/File1
make_file 700 ddd2/aaa/ccc/file2
make_file 700 ddd2/aaa/ccc/.dot1
make_dir  000 zzz/

export HOME=$MOCK_HOME
cd $HOME
cd ddd2

cat >$HOME/.android-devices <<EOF
max
boss
#notused
EOF

# Test for lunch.

assert_comp() {
  if (( $verbose )) ; then
    echo -n "> "
    shescape $@
  fi

  local vars=""

  local OPTIND
  while getopts "v:" opt; do
    case "$opt" in
      v) vars="$OPTARG" ;;
    esac
  done
  shift $(($OPTIND - 1))

  # Note we can't use pipe here, which would break test counting in
  # testutil.bash, so <( ... )
  assert_out -ds cat <("$@" <<<"$vars" | sed -e '1d; $d')
}

test_adb() {
  assert_comp ruby -wx $medir/completer-adb4.rb "$@"
}

test_adb 1 adb <<EOF
'-a '
'-d '
'-e '
'-H '
'-P '
'-s '
'-s2 '
'-s3 '
'-L '
'-f '
'--flags '
'--color '
'--colors '
'-- '
'devices '
'get-devpath '
'get-serialno '
'get-state '
'help '
'kill-server '
'reboot-bootloader '
'remount '
'root '
'start-server '
'unroot '
'usb '
'version '
'wait-for-device '
EOF

test_adb 1 adb - <<EOF
'-a '
'-d '
'-e '
'-H '
'-P '
'-s '
'-s2 '
'-s3 '
'-L '
'-f '
'--flags '
'--color '
'--colors '
'-- '
EOF

export ADB_MOCK_OUT='List of devices attached
SERIALNUMBER1    device
SERIALNUMBER2    device
other_device     device

'

test_adb 2 adb -s <<EOF
'SERIALNUMBER1 '
'SERIALNUMBER2 '
'other_device '
EOF

test_adb 2 adb -s s <<EOF
'SERIALNUMBER1 '
'SERIALNUMBER2 '
EOF

test_adb 2 adb -s o <<EOF
'other_device '
EOF

test_adb 3 adb -s serial <<EOF
'-a '
'-d '
'-e '
'-H '
'-P '
'-s '
'-s2 '
'-s3 '
'-L '
'-f '
'--flags '
'--color '
'--colors '
'-- '
'devices '
'get-devpath '
'get-serialno '
'get-state '
'help '
'kill-server '
'reboot-bootloader '
'remount '
'root '
'start-server '
'unroot '
'usb '
'version '
'wait-for-device '
EOF

test_adb 3 adb -s serial g <<EOF
'get-devpath '
'get-serialno '
'get-state '
EOF

# This is because "maybe" in a loop won't call "next". *1
test_adb 3 adb -s -s2 g <<EOF
'get-devpath '
'get-serialno '
'get-state '
EOF

test_adb 3 adb -s2 serial <<EOF
'SERIALNUMBER1 '
'SERIALNUMBER2 '
'other_device '
EOF

# test_adb 4 adb -s serial -- <<EOF
# 'devices '
# 'get-devpath '
# 'get-serialno '
# 'get-state '
# 'help '
# 'kill-server '
# 'reboot-bootloader '
# 'remount '
# 'root '
# 'start-server '
# 'unroot '
# 'usb '
# 'version '
# 'wait-for-device '
# EOF


done_testing
