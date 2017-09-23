#!/bin/bash

. testutil.bash

# Init files -----------------------------------------------
MOCK_HOME=/tmp/home

cd "${0%/*}"
medir="$(pwd)"

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
make_dir  700 ddd1/aabb
make_file 500 ddd1/bbbb/fff1
make_file 500 ddd1/bbbb/fff2
make_file 500 ddd1/bbbb/FFF3
make_file 500 ddd1/bbbb/aaa
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
EOF

# Test for lunch.

assert_comp() {
  sed -e 's/\^$/ /' | assert_out -d "$@"
}

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch <<EOF
generic-eng^
generic-userdebug^
full-eng^
full-userdebug^
bullhead-eng^
bullhead-userdebug^
angler-eng^
angler-userdebug^
marlin-eng^
marlin-userdebug^
sailfish-eng^
sailfish-userdebug^
walleye-eng^
walleye-userdebug^
taimen-eng^
taimen-userdebug^
max-eng^
max-userdebug^
boss-eng^
boss-userdebug^
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch m  <<EOF
marlin-eng^
marlin-userdebug^
max-eng^
max-userdebug^
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch MA <<EOF
marlin-eng^
marlin-userdebug^
max-eng^
max-userdebug^
EOF

assert_comp ruby -x $medir/completer-lunch.rb -c 1 lunch MA <<EOF
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch MAr <<EOF
marlin-eng^
marlin-userdebug^
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch marlin-e <<EOF
marlin-eng^
EOF

