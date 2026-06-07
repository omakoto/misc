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
    # When --expect is used, fzf outputs the key pressed on the first line.
    # We default to empty string (which represents Enter).
    echo "${MOCK_FZF_KEY:-}"
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
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '4b825dc642cb6eb9a001e5408d69288fbee4904f' ]]"
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
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '4b825dc642cb6eb9a001e5408d69288fbee4904f' ]]"
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
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '4b825dc642cb6eb9a001e5408d69288fbee4904f..${full_commit2}' ]]"

# -------------------------------------------------------------
# Test Case 7: Squash selected commits using ctrl-s
# -------------------------------------------------------------
setup_git_repo
# Create a third commit so we have more history
echo "content3" > file3.txt
git add file3.txt
git config user.name "Test User"
git config user.email "test@example.com"
git commit -q -m "Commit 3"

clear_test_state
commit1_hash=$(git rev-parse --short HEAD~2)
commit2_hash=$(git rev-parse --short HEAD~1)
commit3_hash=$(git rev-parse --short HEAD)

# Select Commit 1 and Commit 3 to squash, passing ctrl-s
export MOCK_FZF_KEY="ctrl-s"
MOCK_FZF_SELECTION="$commit3_hash Commit 3\n$commit1_hash Commit 1"

# We must mock git editor because rebase will prompt for squash message
export GIT_EDITOR="cat"

git-meld-history

# Since the rebase succeeded, let's verify that the commit history is updated.
# Specifically, Commit 3 should be squashed into Commit 1.
# The new history should have 2 commits:
# 1. The combined commit (Commit 1 + Commit 3)
# 2. Commit 2 applied on top of it.
# Let's verify this by checking git log.
assert "[[ \$(git log --oneline | wc -l) -eq 2 ]]"
export MOCK_FZF_KEY=""
unset GIT_EDITOR

# -------------------------------------------------------------
# Test Case 8: Verify branch decoration formatting in fzf stdin
# -------------------------------------------------------------
setup_git_repo
# Create a branch pointing to HEAD
git checkout -b test-branch -q

clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history

# Since test-branch points to Commit 2 (HEAD), fzf_stdin should contain:
# <hash> [master, test-branch] Commit 2
# Let's verify that the decoration is in green and formatted as [test-branch]
head_hash=$(git rev-parse --short HEAD)
# Escape sequence for green is \x1b[32m (grep -E matches literal escape sequences or we can use $'...' in bash)
expected_pattern="${head_hash}.*\[32m\[.*test-branch.*\].*Commit 2"
assert "grep -q -E '$expected_pattern' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 9: Verify commit with (CURRENT) in message is formatted (not bypassed)
# -------------------------------------------------------------
setup_git_repo
# Create a commit message containing '(CURRENT)'
echo "content4" > file4.txt
git add file4.txt
git config user.name "Test User"
git config user.email "test@example.com"
git commit -q -m "Commit mentioning (CURRENT) here"

clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history

# Verify fzf_stdin formatted this commit correctly (i.e. contains the timestamp in brackets and magenta author email)
head_hash=$(git rev-parse --short HEAD)
expected_pattern="${head_hash}.*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*\[35m<test@example.com>.*Commit mentioning \(CURRENT\) here"
assert "grep -q -E '$expected_pattern' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 10: Test git-history-fzf script options
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > untracked.txt
clear_test_state
MOCK_FZF_SELECTION=""

# Run with -c and -h option, checking that fzf receives the correct header and fzf_stdin contains (CURRENT)
git-history-fzf -c -h "Custom Header Title"
assert "grep -q 'Custom Header Title' '$TEST_TMP_DIR/fzf_args'"
assert "grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"

clear_test_state
# Run without -c, checking that fzf_stdin does not contain (CURRENT)
git-history-fzf -h "Another Title"
assert "grep -q 'Another Title' '$TEST_TMP_DIR/fzf_args'"
assert "! grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 11: Run git-meld-history passing target repository directory
# -------------------------------------------------------------
setup_git_repo
clear_test_state
MOCK_FZF_SELECTION=""

# Run from outside the repo, passing the repo directory
cd "$TEST_TMP_DIR"
git-meld-history "$TEST_TMP_DIR/repo"
assert "[[ ! -f '$TEST_TMP_DIR/git_meld_calls' ]]" # Exited without calling git-meld
assert "! grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"

# Return to script directory
cd "$SCRIPT_DIR"

# Complete testing
done_testing
