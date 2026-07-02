#!/bin/bash

. testutil.bash

# Move to the script parent directory
cd ${0%/*}
SCRIPT_DIR=$(pwd)
export PATH="$SCRIPT_DIR:$PATH"

export TARGET_SCRIPT="${TARGET_SCRIPT:-git-meld-history}"

git-meld-history() {
  if [[ "$TARGET_SCRIPT" == "git-meld-history" ]]; then
    command git-meld-history "$@"
  else
    "$TARGET_SCRIPT" "$@"
  fi
}

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -p /tmp/ git-meld-history-test-XXXXXX)
export MOCK_FZF_SELECTION=""
cleanup() {
  if [[ -f "$TEST_TMP_DIR/fzf_debug" ]]; then
    echo "=== fzf_debug ==="
    cat "$TEST_TMP_DIR/fzf_debug"
    echo "================="
  fi
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
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"
echo "$*" > "$TEST_TMP_DIR/fzf_args"
cat > "$TEST_TMP_DIR/fzf_stdin"
echo "MOCK_FZF_SELECTION='$MOCK_FZF_SELECTION' MOCK_FZF_KEY='$MOCK_FZF_KEY'" >> "$TEST_TMP_DIR/fzf_debug"

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
}

setup_mock_fzf

# Create mock git-meld
cat > "$TEST_TMP_DIR/bin/git-meld" <<'EOF'
#!/bin/bash
echo "$*" >> "$TEST_TMP_DIR/git_meld_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/git-meld"

setup_git_templates() {
  # Base template
  rm -rf "$TEST_TMP_DIR/template_repo"
  mkdir -p "$TEST_TMP_DIR/template_repo"
  (
    cd "$TEST_TMP_DIR/template_repo"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    echo "content1" > file1.txt
    git add file1.txt
    git commit -q -m "Commit 1"
    
    echo "content2" > file2.txt
    git add file2.txt
    git commit -q -m "Commit 2"
  )

  # Submodule template
  rm -rf "$TEST_TMP_DIR/template_subrepo"
  mkdir -p "$TEST_TMP_DIR/template_subrepo"
  (
    cd "$TEST_TMP_DIR/template_subrepo"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "subcontent" > subfile.txt
    git add subfile.txt
    git commit -q -m "Sub Commit"
  )

  rm -rf "$TEST_TMP_DIR/template_repo_with_submodule"
  cp -a "$TEST_TMP_DIR/template_repo" "$TEST_TMP_DIR/template_repo_with_submodule"
  (
    cd "$TEST_TMP_DIR/template_repo_with_submodule"
    git -c protocol.file.allow=always submodule add -q "$TEST_TMP_DIR/template_subrepo" mysub
    git commit -q -m "Add submodule"
  )
}

setup_git_templates

# Helper to setup a test git repository
setup_git_repo() {
  rm -rf "$TEST_TMP_DIR/repo"
  cp -a "$TEST_TMP_DIR/template_repo" "$TEST_TMP_DIR/repo"
  cd "$TEST_TMP_DIR/repo"
  git update-index -q --refresh
}

# Helper to setup a test git repository with a submodule
setup_git_repo_with_submodule() {
  rm -rf "$TEST_TMP_DIR/repo"
  cp -a "$TEST_TMP_DIR/template_repo_with_submodule" "$TEST_TMP_DIR/repo"
  cd "$TEST_TMP_DIR/repo"
  git update-index -q --refresh
  if [[ -d mysub ]]; then
    git -C mysub update-index -q --refresh >/dev/null 2>&1
  fi
}

# Helper to reset state for each test
clear_test_state() {
  rm -f "$TEST_TMP_DIR/fzf_args"
  rm -f "$TEST_TMP_DIR/fzf_stdin"
  rm -f "$TEST_TMP_DIR/fzf_called"
  rm -f "$TEST_TMP_DIR/git_meld_calls"
  rm -f "$TEST_TMP_DIR/fzf_cwds"
  rm -f "$TEST_TMP_DIR/fzf_call_count"
  rm -f "$TEST_TMP_DIR/fzf_debug"
  rm -f "$TEST_TMP_DIR/fzf_calls"
  rm -f "$TEST_TMP_DIR/editor_calls"
  export MOCK_FZF_SELECTION=""
  export MOCK_FZF_KEY=""
  setup_mock_fzf
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

# -------------------------------------------------------------
# Test Case 12: Verify upstream-base decoration formatting in fzf stdin
# -------------------------------------------------------------
setup_git_repo
default_branch=$(git branch --show-current)
# Create a tracking branch and upstream branch
git checkout -b remote-branch -q
echo "content-remote" > file-remote.txt
git add file-remote.txt
git commit -q -m "Commit on upstream branch"
git checkout "$default_branch" -q
git branch --set-upstream-to=remote-branch "$default_branch" -q

clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history

# Since remote-branch is set as upstream for master, the merge-base between
# master (HEAD) and remote-branch is Commit 2 (which is master tip).
# Let's verify that the decoration is in green and formatted as [upstream-base]
head_hash=$(git rev-parse --short HEAD)
expected_pattern="${head_hash}.*\[32m\[.*upstream-base.*\].*Commit 2"
assert "grep -q -E '$expected_pattern' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 13: Verify submodules formatting in fzf stdin
# -------------------------------------------------------------
setup_git_repo_with_submodule


clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history
assert "grep -q '\[Submodules\]' '$TEST_TMP_DIR/fzf_stdin'"
assert "grep -q -E '\[35m\(submodule\)' '$TEST_TMP_DIR/fzf_stdin'"
# No dirty submodule, so no "(All submodules)" entry
assert "! grep -q '(All submodules)' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 14: Verify submodule selection directory switch
# -------------------------------------------------------------
setup_git_repo_with_submodule


clear_test_state
MOCK_FZF_SELECTION="(submodule) mysub"
git-meld-history

# Verify fzf_cwds recorded the two calls:
# 1st: in repository root
# 2nd: in submodule directory
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
cwds=($(cat "$TEST_TMP_DIR/fzf_cwds"))
assert "[[ ${#cwds[@]} -eq 2 ]]"
assert "[[ '${cwds[0]}' == *'/repo' ]]"
assert "[[ '${cwds[1]}' == *'/repo/mysub' ]]"

# -------------------------------------------------------------
# Test Case 15: Verify two-stage submodule selection fzf flow
# -------------------------------------------------------------
setup_git_repo_with_submodule


clear_test_state
# Overwrite fzf mock to handle three calls
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"
echo "$*" >> "$TEST_TMP_DIR/fzf_args_all"

# Count calls
count=0
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  count=$(cat "$TEST_TMP_DIR/fzf_call_count")
fi
count=$((count + 1))
echo "$count" > "$TEST_TMP_DIR/fzf_call_count"

cat > "$TEST_TMP_DIR/fzf_stdin_$count"

if (( count == 1 )); then
  # 1st call: main fzf selector, select "[Submodules]"
  echo ""
  echo "(submodule) [Submodules]"
elif (( count == 2 )); then
  # 2nd call: submodule fzf selector, select "mysub"
  echo "mysub"
else
  # 3rd call: main fzf selector in submodule directory, return empty to break loop
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

git-meld-history

# Verify working directories:
# 1st call: /repo
# 2nd call (submodule selection fzf): also /repo (since it's called by python script before cd!)
# 3rd call: /repo/mysub (after cd!)
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
cwds=($(cat "$TEST_TMP_DIR/fzf_cwds"))
assert "[[ ${#cwds[@]} -eq 3 ]]"
assert "[[ '${cwds[0]}' == *'/repo' ]]"
assert "[[ '${cwds[1]}' == *'/repo' ]]"
assert "[[ '${cwds[2]}' == *'/repo/mysub' ]]"

# Verify stdin of 2nd call (submodule fzf) contained 'mysub'
assert "grep -q 'mysub' '$TEST_TMP_DIR/fzf_stdin_2'"

# -------------------------------------------------------------
# Test Case 16: Verify help flag
# -------------------------------------------------------------
help_output=$(git-meld-history --help)
assert "[[ \"\$help_output\" == *'git-meld-history - Interactive Git history viewer'* ]]"

# -------------------------------------------------------------
# Test Case 17: Limit history to subdirectory when not a top-level git directory
# -------------------------------------------------------------
setup_git_repo
mkdir -p "$TEST_TMP_DIR/repo/subdir"
echo "subcontent" > "$TEST_TMP_DIR/repo/subdir/subfile.txt"
git add subdir/subfile.txt
git config user.name "Test User"
git config user.email "test@example.com"
git commit -q -m "Commit 3 in subdir"

clear_test_state
# Re-create mock fzf that exits on first call (to capture stdin)
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"
echo "$*" > "$TEST_TMP_DIR/fzf_args"
cat > "$TEST_TMP_DIR/fzf_stdin"
echo "" # Empty return to break loop
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Run passing the subdirectory
git-meld-history "$TEST_TMP_DIR/repo/subdir"

# 1. fzf should be run with the subdirectory as pwd
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/fzf_cwds)' == *'/repo/subdir' ]]"

# 2. fzf_stdin should contain "Commit 3 in subdir" but NOT "Commit 2" or "Commit 1"
# because history is limited to that subdirectory!
assert "grep -q 'Commit 3 in subdir' '$TEST_TMP_DIR/fzf_stdin'"
assert "! grep -q 'Commit 2' '$TEST_TMP_DIR/fzf_stdin'"
assert "! grep -q 'Commit 1' '$TEST_TMP_DIR/fzf_stdin'"

# 4. Now let's test that selecting a commit inside the subdirectory limits git-meld to the subdirectory
clear_test_state
commit3_hash=$(git rev-parse --short HEAD)
export MOCK_FZF_SELECTION="$commit3_hash Commit 3 in subdir"

# Re-create mock fzf to return the selection
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
if [[ -f "$TEST_TMP_DIR/fzf_called" ]]; then
  echo ""
else
  touch "$TEST_TMP_DIR/fzf_called"
  echo ""
  echo -e "$MOCK_FZF_SELECTION"
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

git-meld-history "$TEST_TMP_DIR/repo/subdir"

# git-meld should be called without limiting to subdir (should show all files)
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '${commit3_hash}^..${commit3_hash}' ]]"

# Clean up environment
unset MOCK_FZF_SELECTION

## -------------------------------------------------------------
# Test Case 18: Inject (ctrl-k) when dirty (native implementation)
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" >> file1.txt
clear_test_state

# Overwrite fzf mock to handle multiple calls
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
count=0
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  count=$(cat "$TEST_TMP_DIR/fzf_call_count")
fi
count=$((count + 1))
echo "$count" > "$TEST_TMP_DIR/fzf_call_count"

echo "fzf called (count=$count) with args: $*" >> "$TEST_TMP_DIR/fzf_calls"
cat > "$TEST_TMP_DIR/fzf_stdin_$count"

if (( count == 1 )); then
  # 1st call: commit selection, return ctrl-k and commit1_hash
  echo "ctrl-k"
  echo "$MOCK_FZF_SELECTION"
elif (( count == 2 )); then
  # 2nd call: file selection, return file1.txt
  echo " M file1.txt"
else
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

commit1_hash=$(git rev-parse --short HEAD~1)
export MOCK_FZF_SELECTION="$commit1_hash Commit 1"

git-meld-history

# Verify:
# 1. fzf was called three times (first commit, second file selection, third commit exit)
assert "[[ -f '$TEST_TMP_DIR/fzf_calls' ]]"
assert "[[ \$(wc -l < '$TEST_TMP_DIR/fzf_calls') -eq 3 ]]"
# 2. 2nd fzf call's prompt contains the commit subject: "Inject to Commit 1"
assert "grep -q 'Inject to Commit 1' '$TEST_TMP_DIR/fzf_calls'"
# 3. file1.txt changes were injected into Commit 1
assert "git show HEAD~1:file1.txt | grep -q 'dirty changes'"
# 4. Working tree is clean
assert "[[ -z \$(git status --porcelain file1.txt) ]]"

# -------------------------------------------------------------
# Test Case 19: Inject (ctrl-k) error when clean
# -------------------------------------------------------------
setup_git_repo
clear_test_state

# Mock fzf that returns ctrl-k key on first call, and empty on second to avoid infinite loop
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
if [[ -f "$TEST_TMP_DIR/fzf_called" ]]; then
  echo ""
else
  touch "$TEST_TMP_DIR/fzf_called"
  echo "ctrl-k"
  echo "$MOCK_FZF_SELECTION"
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

commit1_hash=$(git rev-parse --short HEAD~1)
export MOCK_FZF_SELECTION="$commit1_hash Commit 1"

git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that it printed the clean error message
assert "grep -q 'Error: Inject is only available when the worktree is dirty' '$TEST_TMP_DIR/git_meld_err'"

# -------------------------------------------------------------
# Test Case 20: --bash-completion
# -------------------------------------------------------------
assert '[[ "$(git-meld-history --bash-completion)" == *"_git_meld_history"* ]]'

# -------------------------------------------------------------
# Test Case 21: Run without arguments from a subdirectory
# -------------------------------------------------------------
setup_git_repo
mkdir -p "$TEST_TMP_DIR/repo/subdir"
clear_test_state

# Re-create mock fzf that writes to fzf_cwds and exits immediately
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"
echo "" # Empty return to break loop
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

cd "$TEST_TMP_DIR/repo/subdir"

# Run git-meld-history without arguments (which should cd to git toplevel repo dir)
git-meld-history

# Verify:
# 1. fzf should be run with the repository root as pwd, not the subdirectory
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/fzf_cwds)' == *'/repo' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/fzf_cwds)' != *'/repo/subdir' ]]"

# Return to script directory
cd "$SCRIPT_DIR"

# -------------------------------------------------------------
# Test Case 22: Verify parent selection traversal (Parent)
# -------------------------------------------------------------
setup_git_repo_with_submodule


clear_test_state
rm -f "$TEST_TMP_DIR/fzf_call_count"

# Re-create mock fzf to simulate selecting "(Parent)" on first call
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"

# Count calls
count=0
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  count=$(cat "$TEST_TMP_DIR/fzf_call_count")
fi
count=$((count + 1))
echo "$count" > "$TEST_TMP_DIR/fzf_call_count"

if (( count == 1 )); then
  # 1st call: select "(Parent)"
  echo ""
  echo "(submodule) (Parent)"
else
  # 2nd call: return empty to break loop
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Start in the submodule directory
cd "$TEST_TMP_DIR/repo/mysub"

git-meld-history

# Verify:
# 1st call should be in the submodule directory (/repo/mysub)
# 2nd call should be in the parent repository directory (/repo) after cd'ing to Parent
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
cwds=($(cat "$TEST_TMP_DIR/fzf_cwds"))
assert "[[ ${#cwds[@]} -eq 2 ]]"
assert "[[ '${cwds[0]}' == *'/repo/mysub' ]]"
assert "[[ '${cwds[1]}' == *'/repo' ]]"

# Return to script directory
cd "$SCRIPT_DIR"

# -------------------------------------------------------------
# Test Case 23: Edit commit message using ctrl-g
# -------------------------------------------------------------
setup_git_repo
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)

export MOCK_FZF_KEY="ctrl-g"
MOCK_FZF_SELECTION="$commit1_hash Commit 1"

export GIT_EDITOR="sed -i 's/Commit 1/Commit 1 Edited/g'"

git-meld-history

# Verify the commit message was indeed edited
assert "git log --format='%s' | grep -q 'Commit 1 Edited'"
export MOCK_FZF_KEY=""
unset GIT_EDITOR

# -------------------------------------------------------------
# Test Case 24: Edit commit message using ctrl-g with dirty repo (autostash)
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > untracked.txt
echo "more changes" >> file2.txt
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)

export MOCK_FZF_KEY="ctrl-g"
MOCK_FZF_SELECTION="$commit1_hash Commit 1"

export GIT_EDITOR="sed -i 's/Commit 1/Commit 1 Edited Dirty/g'"

git-meld-history

# Verify the commit message was edited and dirty changes are preserved
assert "git log --format='%s' | grep -q 'Commit 1 Edited Dirty'"
assert "[[ -f untracked.txt ]]"
assert "git diff file2.txt | grep -q 'more changes'"
export MOCK_FZF_KEY=""
unset GIT_EDITOR

# Return to script directory
cd "$SCRIPT_DIR"

# -------------------------------------------------------------
# Test Case 25: Attempting to edit a commit already on remote using ctrl-g (should error)
# -------------------------------------------------------------
setup_git_repo
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
full_commit1_hash=$(git rev-parse HEAD~1)

# Simulate pushing Commit 1 to remote by creating a remote tracking branch pointing to it
git update-ref refs/remotes/origin/master "$full_commit1_hash"

export MOCK_FZF_KEY="ctrl-g"
MOCK_FZF_SELECTION="$commit1_hash Commit 1"

# We capture stderr to check the error message
git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that edit was refused and error message printed
assert "grep -q 'Error: Cannot edit message of commits already on remote' '$TEST_TMP_DIR/git_meld_err'"
# Verify the commit message remains unchanged
assert "git log --format='%s' | grep -q 'Commit 1'"
assert "! git log --format='%s' | grep -q 'Commit 1 Edited'"
export MOCK_FZF_KEY=""

# -------------------------------------------------------------
# Test Case 26: Attempting to squash commits already on remote using ctrl-s (should error)
# -------------------------------------------------------------
setup_git_repo
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
commit2_hash=$(git rev-parse --short HEAD)
full_commit1_hash=$(git rev-parse HEAD~1)

# Simulate pushing Commit 1 to remote
git update-ref refs/remotes/origin/master "$full_commit1_hash"

export MOCK_FZF_KEY="ctrl-s"
MOCK_FZF_SELECTION="$commit2_hash Commit 2\n$commit1_hash Commit 1"

git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify squash was refused and error message printed
assert "grep -q 'Error: Cannot squash commits that are already on remote' '$TEST_TMP_DIR/git_meld_err'"
# Verify the commit history is unchanged (still has 2 commits)
assert "[[ \$(git log --oneline | wc -l) -eq 2 ]]"
export MOCK_FZF_KEY=""

# -------------------------------------------------------------
# Test Case 27: Inject (ctrl-k) on remote commit should error
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > file2.txt
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
full_commit1_hash=$(git rev-parse HEAD~1)

# Simulate pushing Commit 1 to remote
git update-ref refs/remotes/origin/master "$full_commit1_hash"

export MOCK_FZF_KEY="ctrl-k"
MOCK_FZF_SELECTION="$commit1_hash Commit 1"

git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that the inject was refused and error message printed
assert "grep -q 'Error: Cannot inject into commits already on remote' '$TEST_TMP_DIR/git_meld_err'"
# Verify file2.txt is still dirty (injection did not complete)
assert "[[ -n \$(git status --porcelain file2.txt) ]]"
export MOCK_FZF_KEY=""

# -------------------------------------------------------------
# Test Case 28: Inject (ctrl-k) on multiple commits should error
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > file2.txt
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)
commit2_hash=$(git rev-parse --short HEAD)

export MOCK_FZF_KEY="ctrl-k"
MOCK_FZF_SELECTION="$commit2_hash Commit 2\n$commit1_hash Commit 1"

git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that the inject was refused and error message printed
assert "grep -q 'Error: Please select exactly 1 commit to inject into' '$TEST_TMP_DIR/git_meld_err'"
# Verify file2.txt is still dirty
assert "[[ -n \$(git status --porcelain file2.txt) ]]"
export MOCK_FZF_KEY=""

# -------------------------------------------------------------
# Test Case 29: Inject (ctrl-k) on (CURRENT) should error
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > file2.txt
clear_test_state

export MOCK_FZF_KEY="ctrl-k"
MOCK_FZF_SELECTION="(CURRENT) Local changes"

git-meld-history 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that the inject was refused and error message printed
assert "grep -q 'Error: Cannot inject into local changes (CURRENT)' '$TEST_TMP_DIR/git_meld_err'"
# Verify file2.txt is still dirty
assert "[[ -n \$(git status --porcelain file2.txt) ]]"
export MOCK_FZF_KEY=""

# -------------------------------------------------------------
# Test Case 30: Edit files in a commit using ctrl-e
# -------------------------------------------------------------
setup_git_repo
clear_test_state
commit1_hash=$(git rev-parse --short HEAD~1)

# Overwrite fzf mock to handle multiple calls
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
count=0
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  count=$(cat "$TEST_TMP_DIR/fzf_call_count")
fi
count=$((count + 1))
echo "$count" > "$TEST_TMP_DIR/fzf_call_count"

echo "fzf called (count=$count) with args: $*" >> "$TEST_TMP_DIR/fzf_calls"
cat > "$TEST_TMP_DIR/fzf_stdin_$count"

if (( count == 1 )); then
  # 1st call: commit selection, return ctrl-e and commit1_hash
  echo "ctrl-e"
  echo "$MOCK_FZF_SELECTION"
elif (( count == 2 )); then
  # 2nd call: file selection, return file1.txt
  echo "file1.txt"
else
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Create mock editor
cat > "$TEST_TMP_DIR/bin/mock_editor" <<'EOF'
#!/bin/bash
echo "editor called with: $*" >> "$TEST_TMP_DIR/editor_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/mock_editor"
export EDITOR="mock_editor"

export MOCK_FZF_SELECTION="$commit1_hash Commit 1"

git-meld-history

# Verify:
# 1. fzf was called three times (first commit, second file selection, third commit exit)
assert "[[ -f '$TEST_TMP_DIR/fzf_calls' ]]"
assert "[[ \$(wc -l < '$TEST_TMP_DIR/fzf_calls') -eq 3 ]]"
# 2. 2nd fzf call's stdin contains file1.txt (which is in Commit 1)
assert "grep -q 'file1.txt' '$TEST_TMP_DIR/fzf_stdin_2'"
# 3. Editor was called with absolute path to file1.txt
assert "[[ -f '$TEST_TMP_DIR/editor_calls' ]]"
assert "grep -q 'editor called with: .*/repo/file1.txt' '$TEST_TMP_DIR/editor_calls'"
unset EDITOR

# -------------------------------------------------------------
# Test Case 31: Edit files in (CURRENT) using ctrl-e
# -------------------------------------------------------------
setup_git_repo
echo "dirty changes" > untracked.txt
clear_test_state

# Overwrite fzf mock to handle multiple calls
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
count=0
if [[ -f "$TEST_TMP_DIR/fzf_call_count" ]]; then
  count=$(cat "$TEST_TMP_DIR/fzf_call_count")
fi
count=$((count + 1))
echo "$count" > "$TEST_TMP_DIR/fzf_call_count"

echo "fzf called (count=$count) with args: $*" >> "$TEST_TMP_DIR/fzf_calls"
cat > "$TEST_TMP_DIR/fzf_stdin_$count"

if (( count == 1 )); then
  # 1st call: commit selection, return ctrl-e and (CURRENT)
  echo "ctrl-e"
  echo "(CURRENT) Local changes"
elif (( count == 2 )); then
  # 2nd call: file selection, return untracked.txt
  echo "untracked.txt"
else
  echo ""
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

# Create mock editor
cat > "$TEST_TMP_DIR/bin/mock_editor" <<'EOF'
#!/bin/bash
echo "editor called with: $*" >> "$TEST_TMP_DIR/editor_calls"
EOF
chmod +x "$TEST_TMP_DIR/bin/mock_editor"
export EDITOR="mock_editor"

git-meld-history

# Verify:
# 1. fzf was called three times
assert "[[ \$(wc -l < '$TEST_TMP_DIR/fzf_calls') -eq 3 ]]"
# 2. 2nd fzf call's stdin contains untracked.txt
assert "grep -q 'untracked.txt' '$TEST_TMP_DIR/fzf_stdin_2'"
# 3. Editor was called with absolute path to untracked.txt
assert "grep -q 'editor called with: .*/repo/untracked.txt' '$TEST_TMP_DIR/editor_calls'"
unset EDITOR

# -------------------------------------------------------------
# Test Case 32: Verify dirty submodules listing and selection
# -------------------------------------------------------------
setup_git_repo_with_submodule


# Make the submodule dirty
echo "dirty in sub" >> mysub/subfile.txt

clear_test_state
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
echo "$(pwd)" >> "$TEST_TMP_DIR/fzf_cwds"

if [[ -f "$TEST_TMP_DIR/fzf_called" ]]; then
  cat > /dev/null
  echo ""
else
  cat > "$TEST_TMP_DIR/fzf_stdin"
  touch "$TEST_TMP_DIR/fzf_called"
  echo ""
  echo "(submodule) mysub (dirty)"
fi
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

git-meld-history

# Verify:
# 1. fzf_stdin should contain the dirty submodule line: '(submodule) mysub (dirty)'
assert "grep -q 'mysub.*dirty' '$TEST_TMP_DIR/fzf_stdin'"
# 2. fzf was called twice: 1st in repo root, 2nd in submodule repo root
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
cwds=($(cat "$TEST_TMP_DIR/fzf_cwds"))
assert "[[ ${#cwds[@]} -eq 2 ]]"
assert "[[ '${cwds[0]}' == *'/repo' ]]"
assert "[[ '${cwds[1]}' == *'/repo/mysub' ]]"

# -------------------------------------------------------------
# Test Case 33: Run passing a git reference as first argument
# -------------------------------------------------------------
setup_git_repo
clear_test_state

# We run with a branch name "master"
git-meld-history "master" 2> "$TEST_TMP_DIR/git_meld_err"

# Verify that:
# 1. fzf was called in the repository root (not a subdirectory named master)
assert "[[ -f '$TEST_TMP_DIR/fzf_cwds' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/fzf_cwds)' == *'/repo' ]]"
# 2. git-history-fzf was called with 'master'
assert "grep -q 'git-history-fzf.*master' '$TEST_TMP_DIR/git_meld_err'"

# -------------------------------------------------------------
# Test Case 34: Verify only dirty submodule does not show (CURRENT) but shows submodule
# -------------------------------------------------------------
setup_git_repo_with_submodule

# Make the submodule dirty
echo "dirty in sub" >> mysub/subfile.txt

clear_test_state
git-meld-history

# Verify:
# 1. fzf_stdin does NOT contain '(CURRENT)'
assert "! grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"
# 2. fzf_stdin contains the dirty submodule
assert "grep -q 'mysub.*dirty' '$TEST_TMP_DIR/fzf_stdin'"

# -------------------------------------------------------------
# Test Case 35: Verify "(All submodules)" listing and selection
# -------------------------------------------------------------
setup_git_repo_with_submodule

# Make the submodule dirty
echo "dirty in sub" >> mysub/subfile.txt

clear_test_state
MOCK_FZF_SELECTION="(submodule) (All submodules)"
git-meld-history

# Verify:
# 1. fzf_stdin contains the "(All submodules)" entry
assert "grep -q '(All submodules)' '$TEST_TMP_DIR/fzf_stdin'"
# 2. git-meld was invoked with --all-submodules
assert "[[ -f '$TEST_TMP_DIR/git_meld_calls' ]]"
assert "[[ '$(cat $TEST_TMP_DIR/git_meld_calls)' == '--all-submodules' ]]"
# 3. Both fzf calls ran in the repository root (no directory switch)
cwds=($(cat "$TEST_TMP_DIR/fzf_cwds"))
assert "[[ ${#cwds[@]} -eq 2 ]]"
assert "[[ '${cwds[0]}' == *'/repo' ]]"
assert "[[ '${cwds[1]}' == *'/repo' ]]"

# Return to script directory
cd "$SCRIPT_DIR"

# -------------------------------------------------------------
# Test Case 36: Verify "(All submodules)" listing when only parent is dirty
# -------------------------------------------------------------
setup_git_repo_with_submodule

# Make ONLY the parent dirty (not the submodule)
echo "dirty parent content" >> file1.txt

clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history

# Verify:
# 1. fzf_stdin contains the "(All submodules)" entry even though the submodule is clean
assert "grep -q '(All submodules)' '$TEST_TMP_DIR/fzf_stdin'"

# Return to script directory
cd "$SCRIPT_DIR"

# -------------------------------------------------------------
# Test Case 37: Verify "(All submodules)" appears before "(CURRENT)" in fzf_stdin
# -------------------------------------------------------------
setup_git_repo_with_submodule

# Make both the submodule and parent repository dirty
echo "dirty in sub" >> mysub/subfile.txt
echo "dirty parent content" >> file1.txt

clear_test_state
MOCK_FZF_SELECTION=""
git-meld-history

# Verify:
# 1. fzf_stdin contains both entries
assert "grep -q '(All submodules)' '$TEST_TMP_DIR/fzf_stdin'"
assert "grep -q '(CURRENT)' '$TEST_TMP_DIR/fzf_stdin'"
# 2. (All submodules) is listed before (CURRENT) (its line number is smaller)
all_subs_line=$(grep -n '(All submodules)' "$TEST_TMP_DIR/fzf_stdin" | cut -d: -f1)
current_line=$(grep -n '(CURRENT)' "$TEST_TMP_DIR/fzf_stdin" | cut -d: -f1)
assert "[[ \$all_subs_line -lt \$current_line ]]"

# Return to script directory
cd "$SCRIPT_DIR"

# Complete testing
done_testing



