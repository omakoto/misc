#!/bin/bash

. testutil.bash

# Init files -----------------------------------------------
MOCK_HOME=/tmp/home

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
EOF

# Test for lunch.

assert_comp() {
  if (( $verbose )) ; then
    echo -n "> "
    shescape $@
  fi
  sort | assert_out -d cat <("$@" | sort | sed -e 's/ $/^/')
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

#===========================================================
# RG
#===========================================================

assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg --color  <<EOF
always^
auto^
never^
EOF

#assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg --type  <<EOF
#EOF

assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg --context  <<EOF
0^
1^
2^
3^
4^
5^
6^
7^
8^
9^
EOF

#===========================================================
# completer-test
#===========================================================

assert_comp ruby -x $medir/completer-test.rb -i -c 1 xxx <<EOF
--^
--exclude^
--file^
--ignore-file^
--max^
--nice^
--threads^
--image^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- <<EOF
aaa/
--reset^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- "~/" <<EOF
/tmp/home/.android-devices^
/tmp/home/.aa1^
/tmp/home/aa1^
/tmp/home/.aa2^
/tmp/home/aa2^
/tmp/home/.bb1^
/tmp/home/bb1^
/tmp/home/ddd1/
/tmp/home/ddd2/
/tmp/home/zzz/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- "~/d" <<EOF
/tmp/home/ddd1/
/tmp/home/ddd2/
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- "~/Z" <<EOF
/tmp/home/zzz/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- "~/zzz" <<EOF
/tmp/home/zzz/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- "~/zzz/" <<EOF
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --image "~/ddd1/bbbb/" <<EOF
/tmp/home/ddd1/bbbb/aaa.jpg^
/tmp/home/ddd1/bbbb/fff1.jpg^
/tmp/home/ddd1/bbbb/FFF2.jpg^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --image "~/ddd1/bbbb/f" <<EOF
/tmp/home/ddd1/bbbb/fff1.jpg^
/tmp/home/ddd1/bbbb/FFF2.jpg^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --image "~/ddd1/bbbb/F" <<EOF
/tmp/home/ddd1/bbbb/FFF2.jpg^
EOF

# Even with *.jpg mask, all directories should still show up.
assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --image "~/ddd1/b" <<EOF
/tmp/home/ddd1/bbbb/
EOF

echo " Done."
