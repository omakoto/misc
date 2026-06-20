#!/bin/bash
# Test for task-history (interactive tasklog selector).
# Run this test script every time touching task-history.

. testutil.bash

# Move to the script parent directory
cd "${0%/*}"
SCRIPT_DIR=$(pwd)

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -t task-history-test-XXXXXX)
export HOME="$TEST_TMP_DIR"
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

# Create a bin folder in the temp dir for mocks
mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

# Create a dummy tasklog directory
export TASKLOG_DIR="$TEST_TMP_DIR/tasklog"
mkdir -p "$TASKLOG_DIR/2026/06"
touch "$TASKLOG_DIR/2026/06/test1.md"
touch "$TASKLOG_DIR/2026/06/test2.md"

# Copy task-history to temp dir
cp "$SCRIPT_DIR/task-history" "$TEST_TMP_DIR/task-history"
chmod +x "$TEST_TMP_DIR/task-history"

# Mock list-files
cat > "$TEST_TMP_DIR/bin/list-files" <<EOF
#!/bin/bash
echo "$TASKLOG_DIR/2026/06/test1.md"
echo "$TASKLOG_DIR/2026/06/test2.md"
EOF
chmod +x "$TEST_TMP_DIR/bin/list-files"

# Mock fzf
cat > "$TEST_TMP_DIR/bin/fzf" <<EOF
#!/bin/bash
echo "fzf_args: \$*" >> "$TEST_TMP_DIR/fzf_calls"
# Simulate selecting test1.md with home prefix
echo "~/tasklog/2026/06/test1.md"
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Mock 1
cat > "$TEST_TMP_DIR/bin/1" <<EOF
#!/bin/bash
echo "opened: \$*" >> "$TEST_TMP_DIR/1_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/1"

# Mock needs-term to return false (don't need terminal) by default
cat > "$TEST_TMP_DIR/bin/needs-term" <<EOF
#!/bin/bash
exit 1
EOF
chmod +x "$TEST_TMP_DIR/bin/needs-term"

# Assertions:
# 1. Test help option
assert "$TEST_TMP_DIR/task-history --help | grep -q 'Usage:'"

# 2. Test standard run without query
(
  cd "$TEST_TMP_DIR"
  ./task-history
)
assert "grep -q 'opened: $TASKLOG_DIR/2026/06/test1.md' '$TEST_TMP_DIR/1_calls'"
assert "grep -q 'fzf_args:.*--ansi' '$TEST_TMP_DIR/fzf_calls'"
assert "grep -q 'fzf_args:.*--no-sort' '$TEST_TMP_DIR/fzf_calls'"

# 3. Test run with query
rm -f "$TEST_TMP_DIR/fzf_calls"
(
  cd "$TEST_TMP_DIR"
  ./task-history my-special-query
)
assert "grep -q 'fzf_args:.*--query my-special-query' '$TEST_TMP_DIR/fzf_calls'"

# 4. Test preview-file option
assert "$TEST_TMP_DIR/task-history --preview-file $TASKLOG_DIR/2026/06/test1.md"

done_testing
