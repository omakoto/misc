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


# Test cases for reverse normalization (-r option)

# Reverse HOME replacement
assert_out ./dir-normalize -r "~" <<EOF
/home/user
EOF

assert_out ./dir-normalize -r "~/foo" <<EOF
/home/user/foo
EOF

assert_out ./dir-normalize -r "~/foo/bar" <<EOF
/home/user/foo/bar
EOF

# Reverse cbin replacement
assert_out ./dir-normalize -r "~/c" <<EOF
/home/user/cbin
EOF

assert_out ./dir-normalize -r "~/c/foo" <<EOF
/home/user/cbin/foo
EOF

# Reverse /android/ prefix
assert_out ./dir-normalize -r "/a/foo" <<EOF
/android/foo
EOF

assert_out ./dir-normalize -r "/a/m" <<EOF
/android/main
EOF

assert_out ./dir-normalize -r "/a/m1" <<EOF
/android/main1
EOF

assert_out ./dir-normalize -r "/a/mabc" <<EOF
/android/mainabc
EOF

assert_out ./dir-normalize -r "/a/m/foo" <<EOF
/android/main/foo
EOF

assert_out ./dir-normalize -r "/a/m1/foo" <<EOF
/android/main1/foo
EOF

assert_out ./dir-normalize -r "/a/mwv" <<EOF
/android/main-without-vendor
EOF

assert_out ./dir-normalize -r "/a/mwv2" <<EOF
/android/main-without-vendor2
EOF

assert_out ./dir-normalize -r "/a/mwv-test" <<EOF
/android/main-without-vendor-test
EOF

assert_out ./dir-normalize -r "/a/mwv/foo" <<EOF
/android/main-without-vendor/foo
EOF

# Reverse frameworks/ inside /a/mXXX/ or /a/mwvXXX/
assert_out ./dir-normalize -r "/a/m1/f/" <<EOF
/android/main1/frameworks/
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/" <<EOF
/android/main1/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/core" <<EOF
/android/main1/frameworks/base/core
EOF

assert_out ./dir-normalize -r "/a/m1/f/b" <<EOF
/android/main1/frameworks/base
EOF

assert_out ./dir-normalize -r "/a/mwv2/f/" <<EOF
/android/main-without-vendor2/frameworks/
EOF

assert_out ./dir-normalize -r "/a/mwv2/f/b/" <<EOF
/android/main-without-vendor2/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/m/f/" <<EOF
/android/main/frameworks/
EOF

assert_out ./dir-normalize -r "/a/m/f/b/" <<EOF
/android/main/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/mwv/f/" <<EOF
/android/main-without-vendor/frameworks/
EOF

assert_out ./dir-normalize -r "/a/mwv/f/b/" <<EOF
/android/main-without-vendor/frameworks/base/
EOF

# frameworks/ should NOT be lengthened if not in mainXXX or mwvXXX
assert_out ./dir-normalize -r "/a/foo/frameworks" <<EOF
/android/foo/frameworks
EOF

assert_out ./dir-normalize -r "~/android/main1/frameworks" <<EOF
/home/user/android/main1/frameworks
EOF

assert_out ./dir-normalize -r "/a" <<EOF
/android
EOF

assert_out ./dir-normalize -r "/a/m1/f/foo/f/bar" <<EOF
/android/main1/frameworks/foo/frameworks/bar
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/foo/f/b/bar" <<EOF
/android/main1/frameworks/base/foo/frameworks/base/bar
EOF

done_testing


