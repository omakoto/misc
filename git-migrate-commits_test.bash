#!/bin/bash
# Unit tests for `misc/git-migrate-commits`
#
# Run this test:
#   ./git-migrate-commits_test.bash
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/testutil.bash"

# Move to the script directory
cd "$DIR"

# Silence the `ee` command printing to keep outputs clean
export EE_QUIET=1

# Create a temp directory for our test repositories
TEST_TMP_DIR=$(mktemp -d)
trap "rm -rf $TEST_TMP_DIR" EXIT

SRC_REPO="$TEST_TMP_DIR/src_repo"
DST_REPO="$TEST_TMP_DIR/dst_repo"

# Initialize source repository
mkdir -p "$SRC_REPO"
git -C "$SRC_REPO" init -b main
git -C "$SRC_REPO" config user.email "test@example.com"
git -C "$SRC_REPO" config user.name "Test User"
git -C "$SRC_REPO" config commit.gpgsign false

# Initialize destination repository
mkdir -p "$DST_REPO"
git -C "$DST_REPO" init -b main
git -C "$DST_REPO" config user.email "test@example.com"
git -C "$DST_REPO" config user.name "Test User"
git -C "$DST_REPO" config commit.gpgsign false

# Make an initial commit in destination so it has a HEAD
touch "$DST_REPO/init.txt"
git -C "$DST_REPO" add init.txt
git -C "$DST_REPO" commit -m "Initial commit in dst"

# Make some commits in source repository
cd "$SRC_REPO"
echo "file1 content" > file1.txt
git add file1.txt
git commit -m "Commit 1"
C1=$(git rev-parse HEAD)

echo "file2 content" > file2.txt
git add file2.txt
git commit -m "Commit 2"
C2=$(git rev-parse HEAD)

echo "file3 content" > file3.txt
git add file3.txt
git commit -m "Commit 3"
C3=$(git rev-parse HEAD)

# Go back to SCRIPT_DIR
cd "$DIR"

# Helper to run the test
run_test_migration() {
  local mock_fzf_output="$1"
  shift

  # Create a mock git-history-fzf script
  local mock_fzf="$TEST_TMP_DIR/mock-git-history-fzf"
  cat <<EOF > "$mock_fzf"
#!/bin/bash
echo -e "$mock_fzf_output"
EOF
  chmod +x "$mock_fzf"

  # Run git-migrate-commits from the source repository directory
  (
    cd "$SRC_REPO"
    export GIT_HISTORY_FZF="$mock_fzf"
    "$DIR/git-migrate-commits" "$@"
  )
}

# Test Case 1: Migrate a single commit (C2)
mock_out_c2="$C2 [2026-06-09] <test@example.com> Commit 2"

assert "run_test_migration \"$mock_out_c2\" \"$DST_REPO\""

# Verify files in DST_REPO
assert "[[ -f \"$DST_REPO/file2.txt\" ]]"
assert "[[ \$(cat \"$DST_REPO/file2.txt\") == \"file2 content\" ]]"
assert "[[ ! -f \"$DST_REPO/file1.txt\" ]]"
assert "[[ ! -f \"$DST_REPO/file3.txt\" ]]"

# Test Case 2: Migrate multiple commits (C1 and C3)
# Reset DST_REPO first
git -C "$DST_REPO" reset --hard HEAD~1
rm -f "$DST_REPO/file1.txt" "$DST_REPO/file2.txt" "$DST_REPO/file3.txt"

# Mock fzf to output C3 and C1 (newest first)
mock_out_c3_c1="$C3 [2026-06-09] <test@example.com> Commit 3\n$C1 [2026-06-09] <test@example.com> Commit 1"

assert "run_test_migration \"$mock_out_c3_c1\" \"$DST_REPO\""

# Verify files
assert "[[ -f \"$DST_REPO/file1.txt\" ]]"
assert "[[ -f \"$DST_REPO/file3.txt\" ]]"
assert "[[ ! -f \"$DST_REPO/file2.txt\" ]]"

# Verify order of commits
print_dst_log() {
  git -C "$DST_REPO" log --format=%s | head -n 3
}

assert_out -d print_dst_log <<'EOF'
Commit 3
Commit 1
Initial commit in dst
EOF


# Test Case 3: Target directory is a subdirectory
# Reset DST_REPO to initial commit (oldest commit)
git -C "$DST_REPO" reset --hard $(git -C "$DST_REPO" rev-list --max-parents=0 HEAD)
rm -f "$DST_REPO/file1.txt" "$DST_REPO/file2.txt" "$DST_REPO/file3.txt"

DST_SUBDIR="$DST_REPO/sub/dir"
mkdir -p "$DST_SUBDIR"

# Mock fzf to output C2
mock_out_c2="$C2 [2026-06-09] <test@example.com> Commit 2"

assert "run_test_migration \"$mock_out_c2\" \"$DST_SUBDIR\""

# Verify files in DST_REPO
assert "[[ -f \"$DST_REPO/file2.txt\" ]]"
assert "[[ \$(cat \"$DST_REPO/file2.txt\") == \"file2 content\" ]]"

# Test Case 4: Autostash with dirty working directory in target repository
# Reset DST_REPO to initial commit
git -C "$DST_REPO" reset --hard $(git -C "$DST_REPO" rev-list --max-parents=0 HEAD)
rm -f "$DST_REPO/file1.txt" "$DST_REPO/file2.txt" "$DST_REPO/file3.txt"

# Make dirty modifications in DST_REPO
echo "dirty uncommitted content" >> "$DST_REPO/init.txt"

mock_out_c2="$C2 [2026-06-09] <test@example.com> Commit 2"
assert "run_test_migration \"$mock_out_c2\" \"$DST_REPO\""

# Verify that commit was applied and dirty change was restored
assert "[[ -f \"$DST_REPO/file2.txt\" ]]"
assert "[[ \$(cat \"$DST_REPO/file2.txt\") == \"file2 content\" ]]"
assert "[[ \$(cat \"$DST_REPO/init.txt\") == *\"dirty uncommitted content\"* ]]"
assert "[[ -n \$(git -C \"$DST_REPO\" status --porcelain --untracked-files=no) ]]"

# Test Case 5: --no-autostash fails when working tree has conflicts with patch
# Reset DST_REPO and create an uncommitted modification to a file that the patch touches
git -C "$DST_REPO" reset --hard HEAD~1
rm -f "$DST_REPO/file1.txt" "$DST_REPO/file2.txt" "$DST_REPO/file3.txt"
echo "initial file2 content" > "$DST_REPO/file2.txt"
git -C "$DST_REPO" add file2.txt
git -C "$DST_REPO" commit -m "Add file2 in dst"
echo "uncommitted conflicting edit" >> "$DST_REPO/file2.txt"

assert "! run_test_migration \"$mock_out_c2\" --no-autostash \"$DST_REPO\""
# Clean up the failed am session
git -C "$DST_REPO" am --abort 2>/dev/null || true

# Test Case 6: Explicit --autostash flag with staged changes
# Reset DST_REPO
git -C "$DST_REPO" reset --hard $(git -C "$DST_REPO" rev-list --max-parents=0 HEAD)
rm -f "$DST_REPO/file1.txt" "$DST_REPO/file2.txt" "$DST_REPO/file3.txt"
echo "staged content" >> "$DST_REPO/init.txt"
git -C "$DST_REPO" add init.txt

assert "run_test_migration \"$mock_out_c2\" --autostash \"$DST_REPO\""
assert "[[ -f \"$DST_REPO/file2.txt\" ]]"
assert "[[ \$(cat \"$DST_REPO/init.txt\") == *\"staged content\"* ]]"

# Test Case 7: Error handling for invalid options and non-git target
NON_GIT_DIR="$TEST_TMP_DIR/nongit"
mkdir -p "$NON_GIT_DIR"
assert "! \"$DIR/git-migrate-commits\" \"$NON_GIT_DIR\""
assert "! \"$DIR/git-migrate-commits\" --invalid-flag \"$DST_REPO\""

# Test Case 8: --bash-completion
assert '[[ "$("$DIR/git-migrate-commits" --bash-completion)" == *"_git_migrate_commits"* ]]'
assert '[[ "$("$DIR/git-migrate-commits" --bash-completion)" == *"--autostash"* ]]'
assert '[[ "$("$DIR/git-migrate-commits" --bash-completion)" == *"--no-autostash"* ]]'

done_testing

