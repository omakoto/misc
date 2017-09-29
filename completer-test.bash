#!/bin/bash

. testutil.bash

# Init files -----------------------------------------------
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
make_dir  700 ddd2/dir2
make_file 400 ddd2/file1
make_dir  000 zzz/

export HOME=$MOCK_HOME
cd $HOME
cd ddd2

cat >$HOME/.android-devices <<EOF
max
boss
#notused
EOF

assert_comp() {
  if (( $verbose )) ; then
    echo -n "> "
    shescape "$@"
  fi

  # Note we can't use pipe here, which would break test counting in
  # testutil.bash, so <( ... )
  assert_out -ds cat <("$@" <<<"$VARS" | sed -e '1d; $d')
}

assert_raw_comp() {
  assert_comp ruby -I "$medir" "$@"
}

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch <<EOF
'generic-eng '
'generic-userdebug '
'full-eng '
'full-userdebug '
'bullhead-eng '
'bullhead-userdebug '
'angler-eng '
'angler-userdebug '
'marlin-eng '
'marlin-userdebug '
'sailfish-eng '
'sailfish-userdebug '
'walleye-eng '
'walleye-userdebug '
'taimen-eng '
'taimen-userdebug '
'max-eng '
'max-userdebug '
'boss-eng '
'boss-userdebug '
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch m  <<EOF
'marlin-eng '
'marlin-userdebug '
'max-eng '
'max-userdebug '
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch MA <<EOF
'marlin-eng '
'marlin-userdebug '
'max-eng '
'max-userdebug '
EOF

assert_comp ruby -x $medir/completer-lunch.rb -c 1 lunch MA <<EOF
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch MAr <<EOF
'marlin-eng '
'marlin-userdebug '
EOF

assert_comp ruby -x $medir/completer-lunch.rb -i -c 1 lunch marlin-e <<EOF
'marlin-eng '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      candidates %w(aaa aab abb ccc)
    end
    ' -- -ic 1 cat <<'EOF'
'aaa '
'aab '
'abb '
'ccc '
EOF

# If main() is defined, call it too.
assert_raw_comp -e 'require "completer"
    Completer.define do
      def main
        candidates %w(aaa aab abb ccc)
      end
    end
    ' -- -ic 1 cat <<'EOF'
'aaa '
'aab '
'abb '
'ccc '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      candidates %w(aaa aab abb ccc)
    end
    ' -- -ic 1 cat a <<'EOF'
'aaa '
'aab '
'abb '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      candidates %w(aaa aab abb ccc)
    end
    ' -- -ic 1 cat Aa <<'EOF'
'aaa '
'aab '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      candidates %w(aaa aab abb ccc)
    end
    ' -- -c 1 cat Aa <<'EOF'
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      for_arg do
        candidates %w(aaa aab abb ccc)
      end
    end
    ' -- -ic 2 cat xyz <<'EOF'
'aaa '
'aab '
'abb '
'ccc '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_file
    end
    ' -- -ic 1 cat <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 1 cat <<'EOF'
'aaa '
'bbb '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 1 cat a <<'EOF'
'aaa '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 2 cat a <<'EOF'
'xxx '
'yyy '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 3 cat a x <<'EOF'
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      maybe %w(-a -b -c)
      maybe "--colors", %w(always never auto)
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 1 cat <<'EOF'
'-a '
'-b '
'-c '
'--colors '
'aaa '
'bbb '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      maybe %w(-a -b -c)
      maybe "--colors", %w(always never auto)
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 1 cat - <<'EOF'
'-a '
'-b '
'-c '
'--colors '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      maybe %w(-a -b -c)
      maybe "--colors", %w(always never auto)
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 1 cat -- <<'EOF'
'--colors '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      maybe %w(-a -b -c)
      maybe "--colors", %w(always never auto)
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 2 cat --colors <<'EOF'
'auto '
'always '
'never '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      maybe %w(-a -b -c)
      maybe "--colors", %w(always never auto)
      next_arg_must %w(aaa bbb), %w(xxx yyy)
    end
    ' -- -ic 3 cat --colors always <<'EOF'
'aaa '
'bbb '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      for_arg do
        next_arg_must take_file
      end
    end
    ' -- -ic 1 cat <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      for_arg do
        next_arg_must take_file
      end
    end
    ' -- -ic 2 cat x <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      for_arg do
        next_arg_must take_file
      end
    end
    ' -- -ic 2 cat x aaa/ <<'EOF'
'aaa/bbb/ '
aaa/ccc/
EOF

# Environmental variable completion.

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -ic 1 cat '$' <<'EOF'
'$HOME'
'$HOST'
'$hostname'
'$PATH'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -ic 1 cat '$h' <<'EOF'
'$HOME'
'$HOST'
'$hostname'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -c 1 cat '$h' <<'EOF'
'$hostname'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -c 1 cat '$HOME' <<'EOF'
'$HOME'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -c 1 cat '$HOME/' <<'EOF'
/tmp/home/
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" assert_raw_comp -e 'require "completer"
    Completer.define {} # body does not matter for this test
    ' -- -c 1 cat '$PATH/' <<'EOF'
EOF

# Special casing redirect operators.

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 1 cat <<'EOF'
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 2 cat '<' <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 2 cat '<<<' <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 2 cat '>' <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 2 cat '>>' <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
    end
    ' -- -ic 2 cat '>!' <<'EOF'
aaa/
'dir2/ '
'file1 '
EOF

# ==============================================================================
# Numbers
# ==============================================================================

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_number
    end
    ' -- -ic 1 cat <<'EOF'
'0 '
'1 '
'2 '
'3 '
'4 '
'5 '
'6 '
'7 '
'8 '
'9 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_number
    end
    ' -- -ic 1 cat 2 <<'EOF'
'20 '
'21 '
'22 '
'23 '
'24 '
'25 '
'26 '
'27 '
'28 '
'29 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_number allow_negative:true
    end
    ' -- -ic 1 cat <<'EOF'
'0 '
'1 '
'2 '
'3 '
'4 '
'5 '
'6 '
'7 '
'8 '
'9 '
'-1 '
'-2 '
'-3 '
'-4 '
'-5 '
'-6 '
'-7 '
'-8 '
'-9 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_number allow_negative:true
    end
    ' -- -ic 1 cat 3 <<'EOF'
'30 '
'31 '
'32 '
'33 '
'34 '
'35 '
'36 '
'37 '
'38 '
'39 '
EOF

assert_raw_comp -e 'require "completer"
    Completer.define do
      next_arg_must take_number allow_negative:true
    end
    ' -- -ic 1 cat -3 <<'EOF'
'-30 '
'-31 '
'-32 '
'-33 '
'-34 '
'-35 '
'-36 '
'-37 '
'-38 '
'-39 '
EOF


# ==============================================================================
# ADB TEST
# ==============================================================================
test_adb() {
  ADB_TEST_COMP=1 assert_comp ruby -wx $medir/completer-adb.rb -ic "$@"
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
'install '
'install-multiple '
'help '
'kill-server '
'pull '
'push '
'reboot-bootloader '
'remount '
'root '
'start-server '
'uninstall '
'unroot '
'usb '
'version '
'wait-for-device '
'logcat '
'reboot '
'shell '
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
'install '
'install-multiple '
'help '
'kill-server '
'pull '
'push '
'reboot-bootloader '
'remount '
'root '
'start-server '
'uninstall '
'unroot '
'usb '
'version '
'wait-for-device '
'logcat '
'reboot '
'shell '
EOF

test_adb 3 adb -s serial g <<EOF
'get-devpath '
'get-serialno '
'get-state '
EOF

test_adb 3 adb -s -s2 s<<EOF
'shell '
'start-server '
EOF

test_adb 3 adb -s2 serial <<EOF
'SERIALNUMBER1 '
'SERIALNUMBER2 '
'other_device '
EOF

test_adb 4 adb -s serial -- <<EOF
'devices '
'get-devpath '
'get-serialno '
'get-state '
'install '
'install-multiple '
'help '
'kill-server '
'pull '
'push '
'reboot-bootloader '
'remount '
'root '
'start-server '
'uninstall '
'unroot '
'usb '
'version '
'wait-for-device '
'logcat '
'reboot '
'shell '
EOF

export ADB_MOCK_OUT='/default.prop
/data/
/system/'

test_adb 2 adb pull <<EOF
/data/
/default.prop
/system/
EOF

test_adb 3 adb pull /data  <<EOF
aaa/
'dir2/ '
'file1 '
EOF

test_adb 2 adb push  <<EOF
aaa/
'dir2/ '
'file1 '
EOF

test_adb 2 adb push a <<EOF
aaa/
EOF

test_adb 3 adb push aaa <<EOF
/data/
/default.prop
/system/
EOF

test_adb 3 adb push aaa /d <<EOF
/data/
/default.prop
EOF

export ADB_MOCK_OUT='package:android
package:com.android.systemui
package:com.android.settings'

test_adb 2 adb uninstall <<EOF
'android '
'com.android.settings '
'com.android.systemui '
'-k '
EOF

test_adb 2 adb uninstall - <<EOF
'-k '
EOF

test_adb 2 adb uninstall com <<EOF
'com.android.settings '
'com.android.systemui '
EOF

test_adb 3 adb uninstall -k <<EOF
'android '
'com.android.settings '
'com.android.systemui '
EOF

test_adb 2 adb install <<EOF
'-a '
'-d '
'-e '
'-H '
'-P '
aaa/
'dir2/ '
'file1 '
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$' <<'EOF'
'$HOME'
'$HOST'
'$hostname'
'$PATH'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$h' <<'EOF'
'$HOME'
'$HOST'
'$hostname'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$p' <<'EOF'
'$PATH'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$home' <<'EOF'
'$HOME'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$HOME' <<'EOF'
'$HOME'
EOF

VARS="declare -- HOME=$HOME
declare -- HOST=hostname
declare -- hostname=hostname.domain.com
declare -- PATH=\"a:b:c\"" test_adb 1 adb '$HOME/' <<'EOF'
/tmp/home/
EOF

export ADB_MOCK_OUT='/default.prop
/data/
/system/'

test_adb 2 adb cat <<EOF
/data/
/default.prop
/system/
EOF

done_testing
