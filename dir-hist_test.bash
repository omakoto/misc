#!/bin/bash
# Test for dir-hist command.
# Run this test script every time touching the main script.

. testutil.bash

# Mock HOME to a temporary directory to avoid touching user's files.
TEST_HOME=$(mktemp -d /tmp/dir-hist-test.XXXXXX)
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"

# 1. Add directories
assert_out ./dir-hist -a /foo/bar <<EOF
EOF
# Verify file exists
assert "[[ -f '$HOME/.dir-hist.txt' ]]"
# Verify file structure (dir, time, count=1)
assert "grep -q -P '/foo/bar\t\d+\t1' '$HOME/.dir-hist.txt'"

# 2. Add same directory again -> increment count
assert_out ./dir-hist -a /foo/bar <<EOF
EOF
assert "grep -q -P '/foo/bar\t\d+\t2' '$HOME/.dir-hist.txt'"

# 3. Add a different directory -> prepended to top
assert_out ./dir-hist -a /baz <<EOF
EOF
# /baz should be first
assert "[[ \$(head -n 1 '$HOME/.dir-hist.txt' | cut -f1) == '/baz' ]]"

# 4. Normalization checks (syntactic only, no symlink resolution)
# /a/b/../c should normalize to /a/c
assert_out ./dir-hist -a /a/b/../c <<EOF
EOF
assert "[[ \$(head -n 1 '$HOME/.dir-hist.txt' | cut -f1) == '/a/c' ]]"

# /a/b/../.. should normalize to /
assert_out ./dir-hist -a /a/b/../.. <<EOF
EOF
assert "[[ \$(head -n 1 '$HOME/.dir-hist.txt' | cut -f1) == '/' ]]"

# Trailing slash cleanup
assert_out ./dir-hist -a /xyz/ <<EOF
EOF
assert "[[ \$(head -n 1 '$HOME/.dir-hist.txt' | cut -f1) == '/xyz' ]]"

# Symlink preservation: check that symlinks are NOT resolved
SYMLINK_TARGET="$TEST_HOME/target"
SYMLINK_PATH="$TEST_HOME/symlink"
mkdir -p "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_PATH"

assert_out ./dir-hist -a "$SYMLINK_PATH" <<EOF
EOF
# Verify that the saved path is the symlink path, not the target path
assert "[[ \$(head -n 1 '$HOME/.dir-hist.txt' | cut -f1) == '$SYMLINK_PATH' ]]"

# 5. List mode filtering
# Clear file for clean list testing
> "$HOME/.dir-hist.txt"

NOW=$(date +%s)
H12=$(( NOW - 12 * 3600 ))
H24=$(( NOW - 24 * 3600 ))
H36=$(( NOW - 36 * 3600 ))
D3=$(( NOW - 3 * 86400 ))

printf "/dir-now\t$NOW\t1\n" >> "$HOME/.dir-hist.txt"
printf "/dir-12h\t$H12\t1\n" >> "$HOME/.dir-hist.txt"
printf "/dir-24h\t$H24\t1\n" >> "$HOME/.dir-hist.txt"
printf "/dir-36h\t$H36\t1\n" >> "$HOME/.dir-hist.txt"
printf "/dir-old\t$D3\t1\n" >> "$HOME/.dir-hist.txt"

# -d 0.5 (12 hours ago) should show /dir-now and /dir-12h
assert_out ./dir-hist -d 0.5 <<EOF
/dir-now
/dir-12h
EOF

# -d 1 (24 hours ago) should show /dir-now, /dir-12h, /dir-24h
assert_out ./dir-hist -d 1 <<EOF
/dir-now
/dir-12h
/dir-24h
EOF

# -d 1.5 (36 hours ago) should show /dir-now, /dir-12h, /dir-24h, /dir-36h
assert_out ./dir-hist -d 1.5 <<EOF
/dir-now
/dir-12h
/dir-24h
/dir-36h
EOF

# Default (30 days) should show everything
assert_out ./dir-hist <<EOF
/dir-now
/dir-12h
/dir-24h
/dir-36h
/dir-old
EOF

# 6. Concurrency stress test
> "$HOME/.dir-hist.txt"
for i in {1..20}; do
  ./dir-hist -a "/dir-$i" &
done
wait

# All 20 directories should be in the file
assert "[[ \$(wc -l < '$HOME/.dir-hist.txt') == 20 ]]"

# Check that every dir-1 to dir-20 is present
for i in {1..20}; do
  assert "grep -q -F '/dir-$i' '$HOME/.dir-hist.txt'"
done

done_testing
