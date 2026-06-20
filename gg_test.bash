#!/bin/bash
# Test for gg wrapper.
# Run this test script every time touching gg.

. testutil.bash

# Move to the script parent directory
cd "${0%/*}"
SCRIPT_DIR=$(pwd)

# Setup temp directory for the test under /tmp/
export TEST_TMP_DIR=$(mktemp -d -p /tmp/ gg-test-XXXXXX)
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

# Create a bin folder in the temp dir for mocks
mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

# Copy gg to temp dir so it looks for is-in-agent in temp dir
cp "$SCRIPT_DIR/gg" "$TEST_TMP_DIR/gg"
chmod +x "$TEST_TMP_DIR/gg"

# Mock is-in-agent to return false (not in agent) by default
# We place it in bin/ so it is found in PATH
echo -e "#!/bin/bash\nexit 1" > "$TEST_TMP_DIR/bin/is-in-agent"
chmod +x "$TEST_TMP_DIR/bin/is-in-agent"

# Mock git-meld-history
cat > "$TEST_TMP_DIR/bin/git-meld-history" <<'EOF'
#!/bin/bash
echo "git-meld-history called with: $*" >> "$TEST_TMP_DIR/calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/git-meld-history"

# Setup dummy directories
NON_GIT_DIR="$TEST_TMP_DIR/nongit"
mkdir -p "$NON_GIT_DIR"

GIT_DIR="$TEST_TMP_DIR/gitdir"
mkdir -p "$GIT_DIR"
(
  cd "$GIT_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  touch file
  git add file
  git commit -q -m "init"
)

# Helper to run gg under test
run_gg() {
  (
    cd "$TEST_TMP_DIR"
    ./gg "$@"
  )
}

run_gg_in_dir() {
  local dir="$1"
  shift
  (
    cd "$dir"
    "$TEST_TMP_DIR/gg" "$@"
  )
}

# Test cases

# 1. Non-git directory
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg "$NON_GIT_DIR" 2>&1)
exit_code=$?
assert '[[ $exit_code -ne 0 ]]'
assert '[[ "$out" == *"is not a git repository"* ]]'
assert '[[ ! -f "$TEST_TMP_DIR/calls" ]]'

# 2. Non-existent directory
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg "$TEST_TMP_DIR/doesnotexist" 2>&1)
exit_code=$?
assert '[[ $exit_code -ne 0 ]]'
assert '[[ "$out" == *"does not exist"* ]]'
assert '[[ ! -f "$TEST_TMP_DIR/calls" ]]'

# 3. Git directory
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg "$GIT_DIR" 2>&1)
exit_code=$?
assert '[[ $exit_code -eq 0 ]]'
assert '[[ -f "$TEST_TMP_DIR/calls" ]]'
assert '[[ "$(cat "$TEST_TMP_DIR/calls")" == "git-meld-history called with: '"$GIT_DIR"'" ]]'

# 4. No args in non-git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg 2>&1)
exit_code=$?
assert '[[ $exit_code -ne 0 ]]'
assert '[[ "$out" == *"is not a git repository"* ]]'
assert '[[ ! -f "$TEST_TMP_DIR/calls" ]]'

# 5. No args in git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg_in_dir "$GIT_DIR" 2>&1)
exit_code=$?
assert '[[ $exit_code -eq 0 ]]'
assert '[[ -f "$TEST_TMP_DIR/calls" ]]'
assert '[[ "$(cat "$TEST_TMP_DIR/calls")" == "git-meld-history called with: " ]]'

# 6. Help flag in non-git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg "-h" 2>&1)
exit_code=$?
assert '[[ $exit_code -eq 0 ]]'
assert '[[ -f "$TEST_TMP_DIR/calls" ]]'
assert '[[ "$(cat "$TEST_TMP_DIR/calls")" == "git-meld-history called with: -h" ]]'

# 7. Flags before git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg "--author=Test" "--another-flag" "$GIT_DIR" 2>&1)
exit_code=$?
assert '[[ $exit_code -eq 0 ]]'
assert '[[ -f "$TEST_TMP_DIR/calls" ]]'
assert '[[ "$(cat "$TEST_TMP_DIR/calls")" == "git-meld-history called with: --author=Test --another-flag '"$GIT_DIR"'" ]]'

# 8. Valid git ref inside git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg_in_dir "$GIT_DIR" "master" 2>&1)
exit_code=$?
assert '[[ $exit_code -eq 0 ]]'
assert '[[ -f "$TEST_TMP_DIR/calls" ]]'
assert '[[ "$(cat "$TEST_TMP_DIR/calls")" == "git-meld-history called with: master" ]]'

# 9. Invalid git ref inside git dir
rm -f "$TEST_TMP_DIR/calls"
out=$(run_gg_in_dir "$GIT_DIR" "invalidbranch" 2>&1)
exit_code=$?
assert '[[ $exit_code -ne 0 ]]'
assert '[[ "$out" == *"is not a directory or a valid git reference"* ]]'
assert '[[ ! -f "$TEST_TMP_DIR/calls" ]]'

done_testing
