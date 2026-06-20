#!/bin/bash
#
# git-v_test.bash - Tests for git-v, verifying it prints Git version as an integer.
# Run from the misc/ directory: ./git-v_test.bash
#

. testutil.bash

# Ensure any existing exported git function doesn't interfere initially
unset -f git

# Test 1: Test with the real git version on this system
# (verify it runs successfully and prints a number)
assert "./git-v | grep -qE '^[0-9]+$'"

# Helper to run git-v with a mocked git version string
run_mocked_git_v() {
  export MOCK_GIT_VER="$1"
  git() {
    echo "git version $MOCK_GIT_VER"
  }
  export -f git
  ./git-v
  unset -f git
  unset MOCK_GIT_VER
}

# Test 2: Verify specific version formatting cases
actual_output() {
  run_mocked_git_v "2.53.0"
}
assert_out -d actual_output <<'EOF'
2053000
EOF

actual_output() {
  run_mocked_git_v "2.9.5"
}
assert_out -d actual_output <<'EOF'
2009005
EOF

actual_output() {
  run_mocked_git_v "10.11.12"
}
assert_out -d actual_output <<'EOF'
10011012
EOF

actual_output() {
  run_mocked_git_v "2.34.1.windows.1"
}
assert_out -d actual_output <<'EOF'
2034001
EOF

# Test 3: Test help command option
actual_output() {
  ./git-v --help | head -n 1
}
assert_out -d actual_output <<'EOF'
git-v - Print Git version as a single integer.
EOF

# Test 4: Test invalid arguments (positional)
actual_output() {
  ./git-v some-argument 2>&1 | head -n 1
}
assert_out -d actual_output <<'EOF'
git-v: Unknown option or argument: some-argument
EOF

done_testing
