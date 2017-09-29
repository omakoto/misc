#!/bin/bash

. "${0%/*}/completer-testbase.bash"

# ==============================================================================
# ADB TEST
# ==============================================================================

test_adb() {
  ADB_TEST_COMP=1 assert_comp ruby -wx $compdir/completer-adb-auto.rb -ic "$@"
}

test_adb 1 adb <<EOF
'-a '
'-d '
'-e '
'-H '
'-P '
'-s '
'-L '
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
'-L '
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
'-L '
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

test_adb 3 adb -s -s s<<EOF
'shell '
'start-server '
EOF

test_adb 3 adb -s serial d <<EOF
'devices '
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

export ADB_MOCK_OUT='/default.prop
/data/
/system/'

test_adb 2 adb cat <<EOF
/data/
/default.prop
/system/
EOF

done_testing
