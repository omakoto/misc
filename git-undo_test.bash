#!/bin/bash
# git-undo_test.bash - Integration tests for git-undo
# Run this test script every time you touch git-undo.

. testutil.bash

# Move to the script parent directory
cd ${0%/*}
SCRIPT_DIR=$(pwd)
export PATH="$SCRIPT_DIR:$PATH"

export TARGET_SCRIPT="${TARGET_SCRIPT:-git-undo}"

git-undo() {
  if [[ "$TARGET_SCRIPT" == "git-undo" ]]; then
    command git-undo "$@"
  else
    "$TARGET_SCRIPT" "$@"
  fi
}

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -t git-undo-test-XXXXXX)
export MOCK_FZF_SELECTION=""
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

# Create a bin folder in the temp dir for mocks
mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

# Create mock fzf function
setup_mock_fzf() {
  cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$*" > "$TEST_TMP_DIR/fzf_args"
cat > "$TEST_TMP_DIR/fzf_stdin"
echo -e "$MOCK_FZF_SELECTION"
EOF
  chmod +x "$TEST_TMP_DIR/bin/fzf"
}

setup_mock_fzf

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
  
  # Simulate pushing Commit 1 to remote by creating a remote tracking branch pointing to it
  git update-ref refs/remotes/origin/master $(git rev-parse HEAD)
}

# Helper to reset state for each test
clear_test_state() {
  rm -f "$TEST_TMP_DIR/fzf_args"
  rm -f "$TEST_TMP_DIR/fzf_stdin"
  export MOCK_FZF_SELECTION=""
  setup_mock_fzf
}

get_tag_name() {
  grep 'Creating backup tag: ' "$TEST_TMP_DIR/stdout" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/Creating backup tag: //'
}

# -------------------------------------------------------------
# Test Case 1: Undo a modified file
# -------------------------------------------------------------
setup_git_repo
echo "modified content" >> file1.txt
clear_test_state
export MOCK_FZF_SELECTION="file1.txt"

# Run git-undo
git-undo > "$TEST_TMP_DIR/stdout" 2> "$TEST_TMP_DIR/stderr"

# Verify:
# 1. file1.txt is reverted
assert "[[ '$(cat file1.txt)' == 'content1' ]]"
# 2. Backup tag created and printed
assert "grep -q 'Creating backup tag: .*undo-tag-' '$TEST_TMP_DIR/stdout'"
tag_name=$(get_tag_name)
assert "[[ -n '$tag_name' ]]"
# 3. Check that the tag has the modified content
assert "[[ '$(git show $tag_name:file1.txt)' == *'modified content'* ]]"

# -------------------------------------------------------------
# Test Case 2: Undo an untracked file (should delete it)
# -------------------------------------------------------------
setup_git_repo
echo "untracked content" > file2.txt
clear_test_state
export MOCK_FZF_SELECTION="file2.txt"

git-undo > "$TEST_TMP_DIR/stdout" 2> "$TEST_TMP_DIR/stderr"

# Verify:
# 1. file2.txt is deleted
assert "[[ ! -f file2.txt ]]"
# 2. Tag has the untracked file
tag_name=$(get_tag_name)
assert "[[ -n '$tag_name' ]]"
assert "[[ '$(git show $tag_name:file2.txt)' == 'untracked content' ]]"

# -------------------------------------------------------------
# Test Case 3: Undo only one of two modified/untracked files
# -------------------------------------------------------------
setup_git_repo
echo "modified file1" >> file1.txt
echo "untracked file2" > file2.txt
clear_test_state
export MOCK_FZF_SELECTION="file2.txt"

git-undo > "$TEST_TMP_DIR/stdout" 2> "$TEST_TMP_DIR/stderr"

# Verify:
# 1. file2.txt is deleted
assert "[[ ! -f file2.txt ]]"
# 2. file1.txt remains modified
assert "[[ '$(cat file1.txt)' == *'modified file1'* ]]"
# 3. Tag contains both
tag_name=$(get_tag_name)
assert "[[ -n '$tag_name' ]]"
assert "[[ '$(git show $tag_name:file2.txt)' == 'untracked file2' ]]"
assert "[[ '$(git show $tag_name:file1.txt)' == *'modified file1'* ]]"

# Return to script directory
cd "$SCRIPT_DIR"

# Complete testing
done_testing
