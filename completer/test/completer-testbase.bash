cd "${0%/*}"
compdir="$(pwd)/.."

. ./testutil.bash

verbose=0
if [[ "$1" == "-v" ]] ; then
  verbose=1
  shift
fi

# ==============================================================================
# Sanitize path
# ==============================================================================
RUBY=$(which ruby)
export PATH="$(dirname "$RUBY"):/bin:/usr/bin/"

RUBYOPTS=-w

# ==============================================================================
# Create a virtual home directory under /tmp.
# ==============================================================================
export MOCK_HOME=/tmp/home
export TAB="$(echo -e "\t")"

unset COMPLETER_DEBUG

export SHELL=/bin/bash

umask 0077

unset PS0
unset PS1
unset PS2
unset PS3
unset PS4
unset PROMPT_COMMAND

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
make_file 700 ddd2/aaa/ccc/file2.apk
make_file 700 ddd2/aaa/ccc/.dot1
make_dir  700 ddd2/dir2
make_file 400 ddd2/file1
make_dir  000 zzz/

export HOME=$MOCK_HOME
cd $HOME
cd ddd2

# ==============================================================================
# Test runners.
# ==============================================================================

assert_comp() {
  if (( $verbose )) ; then
    echo -n "> "
    shescape "$@"
  fi

  # Note we can't use pipe here, which would break test counting in
  # testutil.bash, so <( ... )
  assert_out -s cat <("$@" <<<"$VARS" | sed -e '1d; $d')
}

run_ruby() {
  "$RUBY" $RUBYOPTS "$@"
}

assert_raw_comp() {
  assert_comp run_ruby -I "$compdir" "$@"
}
