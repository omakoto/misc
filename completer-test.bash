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
EOF

# Test for lunch.

assert_comp() {
  if (( $verbose )) ; then
    echo -n "> "
    shescape $@
  fi
  # Note we can't use pipe, which would break test counting in testutil.bash

  assert_out -ds cat <("$@" </dev/null | sed -e '1d; $d; s/ $/^/')
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

# This could fail if rg supports a new filetype that stats with any of the following types.
assert_comp bash -c "ruby -x $medir/completer-rg.rb -i -c 2 rg --type y" <<EOF
yacc^
yaml^
yocto^
EOF

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

assert_comp ruby -x $medir/completer-rg.rb -i -c 1 rg  <<EOF
-0^
--^
-a^
-A^
aaa/
--after-context^
-B^
--before-context^
-c^
-C^
--case-sensitive^
--color^
--colors^
--column^
--context^
--context-separator^
--count^
--debug^
--dfa-size-limit^
--encoding^
-F^
--file^
--files^
--files-with-matches^
--files-without-match^
--fixed-strings^
--follow^
-g^
--glob^
-h^
-H^
--heading^
--help^
--hidden^
-i^
--iglob^
--ignore-case^
--ignore-file^
--invert-match^
-j^
-l^
-L^
--line-number^
--line-regexp^
-m^
-M^
--max-columns^
--max-count^
--maxdepth^
--max-filesize^
--mmap^
-n^
-N^
--no-filename^
--no-heading^
--no-ignore^
--no-ignore-parent^
--no-ignore-vcs^
--no-line-number^
--no-messages^
--no-mmap^
--null^
-o^
--only-matching^
-p^
--path-separator^
--pretty^
-q^
--quiet^
--regexp^
--regex-size-limit^
--replace^
-s^
-S^
--smart-case^
--sort-files^
--text^
--threads^
--type^
--type-add^
--type-clear^
--type-not^
-u^
--unrestricted^
-v^
-V^
--version^
--vimgrep^
-w^
--with-filename^
--word-regexp^
-x^
--type-list^
EOF

# --type-list shows up only at pos 1.
assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg -i <<EOF
-0^
--^
-a^
-A^
aaa/
--after-context^
-B^
--before-context^
-c^
-C^
--case-sensitive^
--color^
--colors^
--column^
--context^
--context-separator^
--count^
--debug^
--dfa-size-limit^
--encoding^
-F^
--file^
--files^
--files-with-matches^
--files-without-match^
--fixed-strings^
--follow^
-g^
--glob^
-h^
-H^
--heading^
--help^
--hidden^
-i^
--iglob^
--ignore-case^
--ignore-file^
--invert-match^
-j^
-l^
-L^
--line-number^
--line-regexp^
-m^
-M^
--max-columns^
--max-count^
--maxdepth^
--max-filesize^
--mmap^
-n^
-N^
--no-filename^
--no-heading^
--no-ignore^
--no-ignore-parent^
--no-ignore-vcs^
--no-line-number^
--no-messages^
--no-mmap^
--null^
-o^
--only-matching^
-p^
--path-separator^
--pretty^
-q^
--quiet^
--regexp^
--regex-size-limit^
--replace^
-s^
-S^
--smart-case^
--sort-files^
--text^
--threads^
--type^
--type-add^
--type-clear^
--type-not^
-u^
--unrestricted^
-v^
-V^
--version^
--vimgrep^
-w^
--with-filename^
--word-regexp^
-x^
EOF

# No arguments allowed after --type-list.
assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg --type-list <<EOF
EOF

# Only files are allowed after --.
assert_comp ruby -x $medir/completer-rg.rb -i -c 2 rg -- <<EOF
aaa/
EOF

#===========================================================
# completer-test
#===========================================================

assert_comp ruby -x $medir/completer-test.rb -i -c 1 xxx <<EOF
--^
--exclude^
--file^
--ignore-file^
--directory^
--max^
--nice^
--threads^
--image^
--always-test^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx -- <<EOF
aaa/
--reset^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 3 xxx -- /tmp/ ../ <<EOF
../.aa1^
../aa1^
../.aa2^
../aa2^
../.android-devices^
../.bb1^
../bb1^
../ddd1/
../ddd2/
../zzz/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 5 xxx -- /tmp/ ../ --reset <<EOF
--^
--exclude^
--file^
--ignore-file^
--directory^
--max^
--nice^
--threads^
--image^
--always-test^
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

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --directory "~/" <<EOF
/tmp/home/ddd1/
/tmp/home/ddd2/
/tmp/home/zzz/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --directory "~/d" <<EOF
/tmp/home/ddd1/
/tmp/home/ddd2/
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --directory "~/ddd1" <<EOF
/tmp/home/ddd1/
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --directory "~/ddd1/" <<EOF
/tmp/home/ddd1/aaaa/^
/tmp/home/ddd1/AAAA/^
/tmp/home/ddd1/aabb/^
/tmp/home/ddd1/bbbb/^
EOF

assert_comp ruby -x $medir/completer-test.rb -i -c 2 xxx --directory "~/ddd1/a" <<EOF
/tmp/home/ddd1/aaaa/^
/tmp/home/ddd1/AAAA/^
/tmp/home/ddd1/aabb/^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --directory "~/ddd1/a" <<EOF
/tmp/home/ddd1/aaaa/^
/tmp/home/ddd1/aabb/^
EOF

# Test for numbers

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --threads <<EOF
--^
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
--directory^
--exclude^
--file^
--ignore-file^
--image^
--max^
--nice^
--threads^
--always-test^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --threads 2 <<EOF
20^
21^
22^
23^
24^
25^
26^
27^
28^
29^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --max <<EOF
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

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --max 0 <<EOF
00^
01^
02^
03^
04^
05^
06^
07^
08^
09^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --max 0a <<EOF
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --nice <<EOF
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
-1^
-2^
-3^
-4^
-5^
-6^
-7^
-8^
-9^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --nice 3 <<EOF
30^
31^
32^
33^
34^
35^
36^
37^
38^
39^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --nice -3 <<EOF
-30^
-31^
-32^
-33^
-34^
-35^
-36^
-37^
-38^
-39^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --nice -3x <<EOF
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --always-test <<EOF
aaaa^
EOF

assert_comp ruby -x $medir/completer-test.rb -c 2 xxx --always-test xyz <<EOF
aaaa^
EOF

done_testing
