#!/bin/bash
#
# term-closer_test.bash - Tests for term-closer script.
# Run from the misc/ directory: ./term-closer_test.bash
#

. testutil.bash

cd "${0%/*}"
SCRIPT_DIR=$(pwd)

export TEST_TMP_DIR=$(mktemp -d -t term-closer-test-XXXXXX)
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

cp "$SCRIPT_DIR/term-closer" "$TEST_TMP_DIR/term-closer"
chmod +x "$TEST_TMP_DIR/term-closer"

# 1. Test help option
assert "$TEST_TMP_DIR/term-closer --help | grep -q 'Usage:'"
assert "$TEST_TMP_DIR/term-closer -h | grep -q 'Usage:'"

# 2. Test invalid arguments
assert "! $TEST_TMP_DIR/term-closer --invalid 2>/dev/null"
assert "! $TEST_TMP_DIR/term-closer -i 10 extra_arg 2>/dev/null"

# 3. Test behavior when no TTY can be determined
cat > "$TEST_TMP_DIR/bin/tty" <<'EOF'
#!/bin/bash
echo "not a tty"
EOF
chmod +x "$TEST_TMP_DIR/bin/tty"

cat > "$TEST_TMP_DIR/bin/ps" <<'EOF'
#!/bin/bash
echo "?"
EOF
chmod +x "$TEST_TMP_DIR/bin/ps"

assert "! $TEST_TMP_DIR/term-closer 2>/dev/null"
assert "$TEST_TMP_DIR/term-closer 2>&1 | grep -q 'Cannot determine target TTY'"

# 4. Test timeout and signal execution
touch "$TEST_TMP_DIR/mock_tty"
# Set access time to 1000 seconds ago
old_time=$(( $(date +%s) - 1000 ))
touch -a -d "@$old_time" "$TEST_TMP_DIR/mock_tty"

cat > "$TEST_TMP_DIR/bin/tty" <<EOF
#!/bin/bash
echo "$TEST_TMP_DIR/mock_tty"
EOF
chmod +x "$TEST_TMP_DIR/bin/tty"

cat > "$TEST_TMP_DIR/bin/ps" <<'EOF'
#!/bin/bash
if [[ "$*" =~ "-o pid=" ]]; then
  echo "1111"
  echo "2222"
elif [[ "$*" =~ "-o sid=" ]]; then
  echo "1111"
else
  echo "?"
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/ps"

cat > "$TEST_TMP_DIR/bin/kill" <<EOF
#!/bin/bash
echo "KILL: \$*" >> "$TEST_TMP_DIR/kill_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/kill"

# Run term-closer with 0 interval and 100s timeout (idle time is 1000s, so it should trigger immediately)
rm -f "$TEST_TMP_DIR/kill_calls"
$TEST_TMP_DIR/term-closer -i 0 -t 100

assert "grep -q 'KILL: -HUP 1111 2222' '$TEST_TMP_DIR/kill_calls' || grep -q 'KILL: -HUP 1111' '$TEST_TMP_DIR/kill_calls'"
assert "grep -q 'KILL: -HUP -- -1111' '$TEST_TMP_DIR/kill_calls' || grep -q 'KILL: -HUP -- 1111' '$TEST_TMP_DIR/kill_calls'"

# 5. Test that no signals are sent when TTY is not idle
rm -f "$TEST_TMP_DIR/kill_calls"
# Set access time to now (0 seconds idle)
touch -a "$TEST_TMP_DIR/mock_tty"

# Run term-closer in background with 0.1s interval and 100s timeout, then kill it after 0.2s
$TEST_TMP_DIR/term-closer -i 0.1 -t 100 &
bg_pid=$!
sleep 0.2
kill -9 $bg_pid 2>/dev/null || true
wait $bg_pid 2>/dev/null || true

assert "[[ ! -f '$TEST_TMP_DIR/kill_calls' ]]"

done_testing
