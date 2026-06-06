#!/bin/bash

. testutil.bash

# Move to the script directory
cd ${0%/*}
SCRIPT_DIR=$(pwd)
export PATH="$SCRIPT_DIR:$PATH"

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -t git-rebase-inject-test-XXXXXX)
export MOCK_FZF_FILES=""
export MOCK_FZF_COMMIT=""
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

# Create a bin folder in the temp dir for mocks
mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

# Create mock fzf
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
call_num=1
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  call_num=$(cat "$TEST_TMP_DIR/fzf_call_count")
  call_num=$((call_num + 1))
fi
echo "$call_num" > "$TEST_TMP_DIR/fzf_call_count"

echo "$*" > "$TEST_TMP_DIR/fzf_args_$call_num"
cat > "$TEST_TMP_DIR/fzf_stdin_$call_num"

if (( call_num == 1 )); then
  echo -e "$MOCK_FZF_FILES"
elif (( call_num == 2 )); then
  echo -e "$MOCK_FZF_COMMIT"
else
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Helper to setup a test git repository
setup_git_repo() {
  cd "$TEST_TMP_DIR"
  rm -rf "$TEST_TMP_DIR/repo"
  mkdir -p "$TEST_TMP_DIR/repo"
  cd "$TEST_TMP_DIR/repo"
  
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  
  # Commit 1
  echo -e "initial file1\nline2" > file1.txt
  git add file1.txt
  git commit -q -m "Commit 1"
  
  # Commit 2
  echo -e "initial file2" > file2.txt
  git add file2.txt
  git commit -q -m "Commit 2"
}

# Helper to reset state for each test
clear_test_state() {
  rm -f "$TEST_TMP_DIR"/fzf_args_*
  rm -f "$TEST_TMP_DIR"/fzf_stdin_*
  rm -f "$TEST_TMP_DIR/fzf_call_count"
}

# -------------------------------------------------------------
# Test Case 1: Clean repo (exits with message)
# -------------------------------------------------------------
setup_git_repo
clear_test_state
assert_out -d git-rebase-inject <<'EOF'
No uncommitted changes found.
EOF
assert "[[ ! -f '$TEST_TMP_DIR/fzf_call_count' ]]"

# -------------------------------------------------------------
# Test Case 2: Dirty repo, select file but cancel commit
# -------------------------------------------------------------
setup_git_repo
echo "modified file1" > file1.txt
clear_test_state
MOCK_FZF_FILES=" M file1.txt"
MOCK_FZF_COMMIT=""
git-rebase-inject
assert "[[ \$(cat \$TEST_TMP_DIR/fzf_call_count) == 2 ]]"
assert "[[ -n '$(git status --porcelain)' ]]"

# -------------------------------------------------------------
# Test Case 3: Inject modification into Commit 1
# -------------------------------------------------------------
setup_git_repo
echo "injected change to file1" >> file1.txt
clear_test_state

commit1_hash=$(git rev-parse --short HEAD~1)
MOCK_FZF_FILES=" M file1.txt"
MOCK_FZF_COMMIT="$commit1_hash Commit 1"

git-rebase-inject

# Verify that workspace is clean
assert "[[ -z '$(git status --porcelain)' ]]"
# Verify that Commit 1 contains the injected change
content=$(git show HEAD~1:file1.txt)
assert "[[ '$content' == *'injected change'* ]]"

# -------------------------------------------------------------
# Test Case 4: Inject untracked file into Commit 2
# -------------------------------------------------------------
setup_git_repo
echo "injected new file" > new_file.txt
clear_test_state

commit2_hash=$(git rev-parse --short HEAD)
MOCK_FZF_FILES="?? new_file.txt"
MOCK_FZF_COMMIT="$commit2_hash Commit 2"

git-rebase-inject

# Verify that workspace is clean
assert "[[ -z '$(git status --porcelain)' ]]"
# Verify new_file.txt exists in Commit 2 (now HEAD)
content=$(git show HEAD:new_file.txt)
assert "[[ '$content' == 'injected new file' ]]"

# Complete testing
done_testing
