#!/bin/bash
# list-files-completion_test.sh - Autocomplete test suite for list-files.
# Run this test script to verify autocomplete completions.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../../.."

# 1. Source the completion script under test
. "$SCRIPT_DIR/list-files-completion.sh"

# 2. Setup mock filesystem sandbox for testing file/dir completion
TEST_DIR=$(mktemp -d)
defer() {
  rm -rf "$TEST_DIR"
}
trap defer EXIT

cd "$TEST_DIR"
mkdir -p a b d/e
touch a/x.txt b/y.txt c.txt d/e/z.txt

# 3. Parser and Assertion Helpers
parse_completion_input() {
  local input="$1"

  # Find the 1-based index of the cursor character '|'
  local cursor_idx
  cursor_idx=$(expr index "$input" "|")
  if [[ $cursor_idx -eq 0 ]]; then
    echo "ERROR: Input string must contain a cursor marker '|'" >&2
    exit 1
  fi

  # Set COMP_LINE and COMP_POINT
  COMP_LINE="${input/|/}"
  COMP_POINT=$((cursor_idx - 1))

  # Split COMP_LINE into COMP_WORDS up to the cursor position
  local before_cursor="${COMP_LINE:0:COMP_POINT}"
  COMP_WORDS=()
  local current_word=""
  local in_space=false

  for (( j=0; j<${#before_cursor}; j++ )); do
    local char="${before_cursor:j:1}"
    if [[ "$char" == " " ]]; then
      if ! $in_space; then
        COMP_WORDS+=("$current_word")
        current_word=""
        in_space=true
      fi
    else
      current_word+="$char"
      in_space=false
    fi
  done
  COMP_WORDS+=("$current_word")
  COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
}

failed=0

run_test() {
  # Read the visual input from the first line of stdin
  local input
  if ! IFS= read -r input; then
    echo "ERROR: Empty test case" >&2
    exit 1
  fi

  # Read expected candidates from remaining lines
  local expected=()
  local line
  while IFS= read -r line; do
    expected+=("$line")
  done

  # Parse input string to COMP_LINE, COMP_POINT, COMP_WORDS, COMP_CWORD
  parse_completion_input "$input"

  # Run the completion function
  COMPREPLY=()
  _list_files_completion

  # Compare COMPREPLY with expected candidates
  local actual=("${COMPREPLY[@]}")
  
  local pass=true
  if [[ ${#actual[@]} -ne ${#expected[@]} ]]; then
    pass=false
  else
    for (( i=0; i<${#expected[@]}; i++ )); do
      if [[ "${actual[i]}" != "${expected[i]}" ]]; then
        pass=false
        break
      fi
    done
  fi

  if $pass; then
    echo "PASS: $input"
  else
    echo "FAIL: $input"
    echo "  Expected: (${expected[*]})"
    echo "  Got:      (${actual[*]})"
    failed=1
  fi
}

# 4. Test Cases

# Option triggers
run_test <<'EOF'
list-files -|
-a
--show-all
-d
--show-directories
-F
--show-fullpath
-h
--help
--home-tild
--no-home-tild
-j
--para
-m
--max-depth
-n
--max-files
--no-show-fullpath
--no-show-relative-path
--no-strip-start-dir
-p
--pattern
-r
--reverse
-R
--show-relative-path
--strip-start-dir
--colors
--bash-completion
EOF

# Pattern option value completion (should be empty)
run_test <<'EOF'
list-files -p |
EOF

# Long option triggers
run_test <<'EOF'
list-files --c|
--colors
EOF

# Colors choices
run_test <<'EOF'
list-files --colors |
always
never
auto
EOF

run_test <<'EOF'
list-files --colors al|
always
EOF

run_test <<'EOF'
list-files --colors n|
never
EOF

# File and Directory completions inside mockup sandbox
run_test <<'EOF'
list-files a|
a
EOF

run_test <<'EOF'
list-files d/e/|
d/e/z.txt
EOF

# 5. Summary
if [[ $failed -eq 0 ]]; then
  echo "ALL AUTOCOMPLETE TESTS PASSED!"
else
  echo "SOME AUTOCOMPLETE TESTS FAILED!"
  exit 1
fi
