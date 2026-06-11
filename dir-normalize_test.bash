#!/bin/bash

. testutil.bash

# Mock HOME
export HOME="/home/user"

# Test cases for HOME replacement
assert_out ./dir-normalize "/home/user" <<EOF
~
EOF

assert_out ./dir-normalize "/home/user/foo" <<EOF
~/foo
EOF

assert_out ./dir-normalize "/home/user/foo/bar" <<EOF
~/foo/bar
EOF

# Test cases for cbin replacement
assert_out ./dir-normalize "/home/user/cbin" <<EOF
~/c
EOF

assert_out ./dir-normalize "/home/user/cbin/foo" <<EOF
~/c/foo
EOF

assert_out ./dir-normalize "~/cbin" <<EOF
~/c
EOF

assert_out ./dir-normalize "~/cbin/foo" <<EOF
~/c/foo
EOF

# Test cases for /android/ prefix

assert_out ./dir-normalize "/android/foo" <<EOF
/a/foo
EOF

# Test cases for /android/main[ANY] -> /a/m[ANY]
assert_out ./dir-normalize "/android/main" <<EOF
/a/m
EOF

assert_out ./dir-normalize "/android/main1" <<EOF
/a/m1
EOF

assert_out ./dir-normalize "/android/mainabc" <<EOF
/a/mabc
EOF

assert_out ./dir-normalize "/android/main/foo" <<EOF
/a/m/foo
EOF

assert_out ./dir-normalize "/android/main1/foo" <<EOF
/a/m1/foo
EOF

# Test cases for /android/main-without-vendor[ANY] -> /a/mwv[ANY]
assert_out ./dir-normalize "/android/main-without-vendor" <<EOF
/a/mwv
EOF

assert_out ./dir-normalize "/android/main-without-vendor2" <<EOF
/a/mwv2
EOF

assert_out ./dir-normalize "/android/main-without-vendor-test" <<EOF
/a/mwv-test
EOF

assert_out ./dir-normalize "/android/main-without-vendor/foo" <<EOF
/a/mwv/foo
EOF

# Test cases for frameworks/ -> f/ inside /a/mXXX/ or /a/mwvXXX/
assert_out ./dir-normalize "/android/main1/frameworks" <<EOF
/a/m1/f/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base" <<EOF
/a/m1/f/b/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/" <<EOF
/a/m1/f/b/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/core" <<EOF
/a/m1/f/b/core
EOF

assert_out ./dir-normalize "/android/main-without-vendor2/frameworks" <<EOF
/a/mwv2/f/
EOF

assert_out ./dir-normalize "/android/main-without-vendor2/frameworks/base" <<EOF
/a/mwv2/f/b/
EOF

assert_out ./dir-normalize "/android/main/frameworks" <<EOF
/a/m/f/
EOF

assert_out ./dir-normalize "/android/main/frameworks/base" <<EOF
/a/m/f/b/
EOF

assert_out ./dir-normalize "/android/main-without-vendor/frameworks" <<EOF
/a/mwv/f/
EOF

assert_out ./dir-normalize "/android/main-without-vendor/frameworks/base" <<EOF
/a/mwv/f/b/
EOF


# frameworks/ should NOT be shortened if not in mainXXX or mwvXXX
assert_out ./dir-normalize "/android/foo/frameworks" <<EOF
/a/foo/frameworks
EOF

assert_out ./dir-normalize "/home/user/android/main1/frameworks" <<EOF
~/android/main1/frameworks
EOF

assert_out ./dir-normalize "/android" <<EOF
/a
EOF

assert_out ./dir-normalize "/android/main1/frameworks/foo/frameworks/bar" <<EOF
/a/m1/f/foo/f/bar
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/foo/frameworks/base/bar" <<EOF
/a/m1/f/b/foo/f/b/bar
EOF

done_testing


