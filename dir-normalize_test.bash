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

# Test cases for /android/main[ANY] -> m[ANY]
assert_out ./dir-normalize "/android/main" <<EOF
m
EOF

assert_out ./dir-normalize "/android/main1" <<EOF
m1
EOF

assert_out ./dir-normalize "/android/mainabc" <<EOF
mabc
EOF

assert_out ./dir-normalize "/android/main/foo" <<EOF
m/foo
EOF

assert_out ./dir-normalize "/android/main1/foo" <<EOF
m1/foo
EOF

# Test cases for /android/main-without-vendor[ANY] -> mwv[ANY]
assert_out ./dir-normalize "/android/main-without-vendor" <<EOF
mwv
EOF

assert_out ./dir-normalize "/android/main-without-vendor2" <<EOF
mwv2
EOF

assert_out ./dir-normalize "/android/main-without-vendor-test" <<EOF
mwv-test
EOF

assert_out ./dir-normalize "/android/main-without-vendor/foo" <<EOF
mwv/foo
EOF

# Test cases for frameworks/ -> f/ inside mXXX/ or mwvXXX/
assert_out ./dir-normalize "/android/main1/frameworks" <<EOF
m1/f/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base" <<EOF
m1/f/b/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/" <<EOF
m1/f/b/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/core" <<EOF
m1/f/b/core
EOF

assert_out ./dir-normalize "/android/main-without-vendor2/frameworks" <<EOF
mwv2/f/
EOF

assert_out ./dir-normalize "/android/main-without-vendor2/frameworks/base" <<EOF
mwv2/f/b/
EOF

assert_out ./dir-normalize "/android/main/frameworks" <<EOF
m/f/
EOF

assert_out ./dir-normalize "/android/main/frameworks/base" <<EOF
m/f/b/
EOF

assert_out ./dir-normalize "/android/main-without-vendor/frameworks" <<EOF
mwv/f/
EOF

assert_out ./dir-normalize "/android/main-without-vendor/frameworks/base" <<EOF
mwv/f/b/
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
m1/f/foo/f/bar
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/foo/frameworks/base/bar" <<EOF
m1/f/b/foo/f/b/bar
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

assert_out ./dir-normalize -r "m" <<EOF
/android/main
EOF

assert_out ./dir-normalize -r "/a/m1" <<EOF
/android/main1
EOF

assert_out ./dir-normalize -r "m1" <<EOF
/android/main1
EOF

assert_out ./dir-normalize -r "/a/mabc" <<EOF
/android/mainabc
EOF

assert_out ./dir-normalize -r "mabc" <<EOF
/android/mainabc
EOF

assert_out ./dir-normalize -r "/a/m/foo" <<EOF
/android/main/foo
EOF

assert_out ./dir-normalize -r "m/foo" <<EOF
/android/main/foo
EOF

assert_out ./dir-normalize -r "/a/m1/foo" <<EOF
/android/main1/foo
EOF

assert_out ./dir-normalize -r "m1/foo" <<EOF
/android/main1/foo
EOF

assert_out ./dir-normalize -r "/a/mwv" <<EOF
/android/main-without-vendor
EOF

assert_out ./dir-normalize -r "mwv" <<EOF
/android/main-without-vendor
EOF

assert_out ./dir-normalize -r "/a/mwv2" <<EOF
/android/main-without-vendor2
EOF

assert_out ./dir-normalize -r "mwv2" <<EOF
/android/main-without-vendor2
EOF

assert_out ./dir-normalize -r "/a/mwv-test" <<EOF
/android/main-without-vendor-test
EOF

assert_out ./dir-normalize -r "mwv-test" <<EOF
/android/main-without-vendor-test
EOF

assert_out ./dir-normalize -r "/a/mwv/foo" <<EOF
/android/main-without-vendor/foo
EOF

assert_out ./dir-normalize -r "mwv/foo" <<EOF
/android/main-without-vendor/foo
EOF

# Reverse frameworks/ inside mXXX/ or mwvXXX/
assert_out ./dir-normalize -r "/a/m1/f/" <<EOF
/android/main1/frameworks/
EOF

assert_out ./dir-normalize -r "m1/f/" <<EOF
/android/main1/frameworks/
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/" <<EOF
/android/main1/frameworks/base/
EOF

assert_out ./dir-normalize -r "m1/f/b/" <<EOF
/android/main1/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/core" <<EOF
/android/main1/frameworks/base/core
EOF

assert_out ./dir-normalize -r "m1/f/b/core" <<EOF
/android/main1/frameworks/base/core
EOF

assert_out ./dir-normalize -r "/a/m1/f/b" <<EOF
/android/main1/frameworks/base
EOF

assert_out ./dir-normalize -r "m1/f/b" <<EOF
/android/main1/frameworks/base
EOF

assert_out ./dir-normalize -r "/a/mwv2/f/" <<EOF
/android/main-without-vendor2/frameworks/
EOF

assert_out ./dir-normalize -r "mwv2/f/" <<EOF
/android/main-without-vendor2/frameworks/
EOF

assert_out ./dir-normalize -r "/a/mwv2/f/b/" <<EOF
/android/main-without-vendor2/frameworks/base/
EOF

assert_out ./dir-normalize -r "mwv2/f/b/" <<EOF
/android/main-without-vendor2/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/m/f/" <<EOF
/android/main/frameworks/
EOF

assert_out ./dir-normalize -r "m/f/" <<EOF
/android/main/frameworks/
EOF

assert_out ./dir-normalize -r "/a/m/f/b/" <<EOF
/android/main/frameworks/base/
EOF

assert_out ./dir-normalize -r "m/f/b/" <<EOF
/android/main/frameworks/base/
EOF

assert_out ./dir-normalize -r "/a/mwv/f/" <<EOF
/android/main-without-vendor/frameworks/
EOF

assert_out ./dir-normalize -r "mwv/f/" <<EOF
/android/main-without-vendor/frameworks/
EOF

assert_out ./dir-normalize -r "/a/mwv/f/b/" <<EOF
/android/main-without-vendor/frameworks/base/
EOF

assert_out ./dir-normalize -r "mwv/f/b/" <<EOF
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

assert_out ./dir-normalize -r "m1/f/foo/f/bar" <<EOF
/android/main1/frameworks/foo/frameworks/bar
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/foo/f/b/bar" <<EOF
/android/main1/frameworks/base/foo/frameworks/base/bar
EOF

assert_out ./dir-normalize -r "m1/f/b/foo/f/b/bar" <<EOF
/android/main1/frameworks/base/foo/frameworks/base/bar
EOF

# Test cases for frameworks/base/ravenwood -> f/b/r/
assert_out ./dir-normalize "/android/main1/frameworks/base/ravenwood" <<EOF
m1/f/b/r/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/ravenwood/" <<EOF
m1/f/b/r/
EOF

assert_out ./dir-normalize "/android/main1/frameworks/base/ravenwood/services" <<EOF
m1/f/b/r/services
EOF

# Reverse frameworks/base/ravenwood/
assert_out ./dir-normalize -r "/a/m1/f/b/r/" <<EOF
/android/main1/frameworks/base/ravenwood/
EOF

assert_out ./dir-normalize -r "m1/f/b/r/" <<EOF
/android/main1/frameworks/base/ravenwood/
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/r" <<EOF
/android/main1/frameworks/base/ravenwood
EOF

assert_out ./dir-normalize -r "m1/f/b/r" <<EOF
/android/main1/frameworks/base/ravenwood
EOF

assert_out ./dir-normalize -r "/a/m1/f/b/r/services" <<EOF
/android/main1/frameworks/base/ravenwood/services
EOF

assert_out ./dir-normalize -r "m1/f/b/r/services" <<EOF
/android/main1/frameworks/base/ravenwood/services
EOF

# A relative input that happens to look like a shortened main tree must not
# get its frameworks/ shortened.
assert_out ./dir-normalize "m1/frameworks/base" <<EOF
m1/frameworks/base
EOF

# Reverse: paths starting with / or ~ are never treated as main trees.
assert_out ./dir-normalize -r "~/m1/f/b" <<EOF
/home/user/m1/f/b
EOF

assert_out ./dir-normalize -r "/m1/f/b" <<EOF
/m1/f/b
EOF

# Reverse: f/b/ inside a non-main /a/ path is left alone.
assert_out ./dir-normalize -r "/a/foo/f/b" <<EOF
/android/foo/f/b
EOF

# Multiple paths: one output line per input, in order.
assert_out ./dir-normalize "/android/main1/frameworks/base" "/home/user/cbin" "/android/foo" <<EOF
m1/f/b/
~/c
/a/foo
EOF

assert_out ./dir-normalize -r "mwv2/f/b/r/" "~/c" "/a/foo" <<EOF
/android/main-without-vendor2/frameworks/base/ravenwood/
/home/user/cbin
/android/foo
EOF

done_testing


