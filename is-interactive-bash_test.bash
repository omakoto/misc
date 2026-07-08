#!/bin/bash
#
# is-interactive-bash_test.bash - Tests for is-interactive-bash script.
# Run from the misc/ directory: ./is-interactive-bash_test.bash
#

. testutil.bash

cd "${0%/*}"
SCRIPT_DIR=$(pwd)

export TEST_TMP_DIR=$(mktemp -d -t is-interactive-bash-test-XXXXXX)
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

cp "$SCRIPT_DIR/is-interactive-bash" "$TEST_TMP_DIR/is-interactive-bash"
chmod +x "$TEST_TMP_DIR/is-interactive-bash"

# 1. Help option
assert "$TEST_TMP_DIR/is-interactive-bash --help | grep -q 'Usage:'"
assert "$TEST_TMP_DIR/is-interactive-bash -h | grep -q 'Usage:'"

# 2. Invalid arguments
assert "! $TEST_TMP_DIR/is-interactive-bash --invalid 2>/dev/null"
assert "! $TEST_TMP_DIR/is-interactive-bash -p 100 extra_arg 2>/dev/null"

# Create mock ps to test different session leader scenarios
cat > "$TEST_TMP_DIR/bin/ps" <<'EOF'
#!/bin/bash
pid=""
format=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) pid="$2"; shift 2 ;;
    -o) format="$2"; shift 2 ;;
    *) shift ;;
  esac
done
format="${format%=}"

case "$pid" in
  1000) # Login bash (-bash) -> interactive
    case "$format" in sid) echo 1000 ;; comm) echo "-bash" ;; tty) echo "pts/1" ;; args) echo "-bash" ;; *) echo "?" ;; esac ;;
  1001) # bash -i -> interactive
    case "$format" in sid) echo 1001 ;; comm) echo "bash" ;; tty) echo "pts/1" ;; args) echo "bash -i" ;; *) echo "?" ;; esac ;;
  1002) # top -> non-bash session leader
    case "$format" in sid) echo 1002 ;; comm) echo "top" ;; tty) echo "pts/1" ;; args) echo "top" ;; *) echo "?" ;; esac ;;
  1003) # bash -c -> non-interactive
    case "$format" in sid) echo 1003 ;; comm) echo "bash" ;; tty) echo "pts/1" ;; args) echo "bash -c echo hi" ;; *) echo "?" ;; esac ;;
  1004) # bash script.sh -> non-interactive
    case "$format" in sid) echo 1004 ;; comm) echo "bash" ;; tty) echo "pts/1" ;; args) echo "bash /path/to/script.sh" ;; *) echo "?" ;; esac ;;
  1005) # background bash (no tty) -> non-interactive
    case "$format" in sid) echo 1005 ;; comm) echo "bash" ;; tty) echo "?" ;; args) echo "bash" ;; *) echo "?" ;; esac ;;
  *)
    exec -a ps /bin/ps -o "$format=" -p "$pid" 2>/dev/null || echo "?"
    ;;
esac
EOF
chmod +x "$TEST_TMP_DIR/bin/ps"

# 3. Interactive login bash (-bash, PID 1000)
assert "$TEST_TMP_DIR/is-interactive-bash -p 1000"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1000 -v 2>&1 | grep -q 'is an interactive shell'"

# 4. Interactive explicit bash (-i, PID 1001)
assert "$TEST_TMP_DIR/is-interactive-bash -p 1001"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1001 -v 2>&1 | grep -q 'is an interactive shell'"

# 5. Non-bash session leader (top, PID 1002) -> returns 1
assert "! $TEST_TMP_DIR/is-interactive-bash -p 1002 2>/dev/null"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1002 -v 2>&1 | grep -q 'not '\''bash'\'''"

# 6. Non-interactive bash -c (PID 1003) -> returns 1
assert "! $TEST_TMP_DIR/is-interactive-bash -p 1003 2>/dev/null"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1003 -v 2>&1 | grep -q 'invoked with -c'"

# 7. Non-interactive bash script execution (PID 1004) -> returns 1
assert "! $TEST_TMP_DIR/is-interactive-bash -p 1004 2>/dev/null"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1004 -v 2>&1 | grep -q 'script argument(s)'"

# 8. Background bash with no TTY (PID 1005) -> returns 1
assert "! $TEST_TMP_DIR/is-interactive-bash -p 1005 2>/dev/null"
assert "$TEST_TMP_DIR/is-interactive-bash -p 1005 -v 2>&1 | grep -q 'no controlling TTY'"

# 9. Quiet mode suppresses verbose and error messages
assert "[[ -z \"\$($TEST_TMP_DIR/is-interactive-bash -p 1002 -q -v 2>&1)\" ]]"
assert "[[ -z \"\$($TEST_TMP_DIR/is-interactive-bash -p 1002 -q 2>&1)\" ]]"

done_testing
