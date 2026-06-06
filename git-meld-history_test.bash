#!/bin/bash

. testutil.bash

# Move to the script parent directory
cd ${0%/*}
SCRIPT_DIR=$(pwd)
export PATH="$SCRIPT_DIR:$PATH"

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -t git-meld-history-test-XXXXXX)
export MOCK_FZF_SELECTION=""
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
echo "$*" > "$TEST_TMP_DIR/fzf_args"
cat > "$TEST_TMP_DIR/fzf_stdin"

if [[ -f "$TEST_TMP_DIR/fzf_called" ]]; then
  # Second call: return empty to break the loop
  echo ""
else
  touch "$TEST_TMP_DIR/fzf_called"
  if [[ -n "$MOCK_FZF_SELECTION" ]]; then
    echo -e "$MOCK_FZF_SELECTION"
  fi
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Create mock git-meld
cat > "$TEST_TMP_DIR/bin/git-meld" <<'EOF'
#!/bin/bash
echo "$*" >> "$TEST_TMP_DIR/git_meld_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/git-meld"

# Helper to setup a test git repository
setup_git_repo() {
  rm -rf "$TEST_TMP_DIR/repo"
  mkdir -p "$TEST_TMP_DIR/repo"
  cd "$TEST_TMP_DIR/repo"
  
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  
  # Commit 1
  echo "content1" > file1.txt
  git add file1.txt
  git commit -q -m "Commit 1"
  
  # Commit 2
  echo "content2" > file2.txt
  git add file2.txt
  git commit -q -m "Commit 2"
}

# Helper to reset state for each test
clear_test_state() {
  rm -f "$TEST_TMP_DIR/fzf_args"
  rm -f "$TEST_TMP_DIR/fzf_stdin"
  rm -f "$TEST_TMP_DIR/fzf_called"
  rm -f "$TEST_TMP_DIR/git_meld_calls"
}

# -------------------------------------------------------------
# Test Case 1: Clean repo (no (CURRENT) in fzf stdin)
# -------------------------------------------------------------
setup_git_repo
clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history
assert "[[ ! -f '$TEST_TMP_DIR/git_meld_calls' ]]" # Exited without calling git-meld
assert "! grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"
assert "grep -q -- '--preview' '$TEST_TMP_DIR/fzf_args'"
assert "grep -q -- '--preview-window' '$TEST_TMP_DIR/fzf_args'"

# -------------------------------------------------------------
# Test Case 2: Dirty repo with untracked files ((CURRENT) is present in fzf stdin)
# -------------------------------------------------------------
setup_git_repo
echo "new stuff" > untracked.txt
clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history
assert "grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 3: Solo selection of (CURRENT) (compares HEAD to workspace, including untracked)
# -------------------------------------------------------------
setup_git_repo
echo "new stuff" > untracked.txt
clear_test_state
MOCK_FZF_SELECTION="(CURRENT) Local changes"
git-meld-history
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == 'HEAD' ]]"
# Verify that untracked.txt is still untracked (reset was called)
assert "[[ -n '$(git ls-files --others --exclude-standard)' ]]"

# -------------------------------------------------------------
# Test Case 4: Multi-selection containing (CURRENT) (compares oldest to workspace)
# -------------------------------------------------------------
setup_git_repo
echo "new stuff" > untracked.txt
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
MOCK_FZF_SELECTION="(CURRENT) Local changes\n$commit1_hash Commit 1"
git-meld-history
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == "$commit1_hash"* ]]"
assert "[[ -n '$(git ls-files --others --exclude-standard)' ]]"

# -------------------------------------------------------------
# Test Case 5: Multi-selection with multiple historical commits and (CURRENT)
# -------------------------------------------------------------
setup_git_repo
echo "new stuff" > untracked.txt
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
commit2_hash=$(git rev-parse --short HEAD)
MOCK_FZF_SELECTION="(CURRENT) Local changes\n$commit2_hash Commit 2\n$commit1_hash Commit 1"
git-meld-history
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == "$commit1_hash"* ]]"
assert "[[ -n '$(git ls-files --others --exclude-standard)' ]]"

# -------------------------------------------------------------
# Test Case 6: Standard multi-selection without (CURRENT)
# -------------------------------------------------------------
setup_git_repo
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
commit2_hash=$(git rev-parse --short HEAD)
MOCK_FZF_SELECTION="$commit2_hash Commit 2\n$commit1_hash Commit 1"
git-meld-history
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
full_commit1=$(git rev-parse HEAD~1)
full_commit2=$(git rev-parse HEAD)
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '${full_commit1}..${full_commit2}' ]]"

# Complete testing
done_testing
