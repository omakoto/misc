#!/bin/bash
#
# shescapes_test.bash - Tests for shescapes, verifying shell-escaping from stdin and files.
# Run from the misc/ directory: ./shescapes_test.bash
#

. testutil.bash

# Ensure shescapes is runnable and test standard input
test_stdin_simple() {
  echo "hello world" | ./shescapes
}
assert_out -d test_stdin_simple <<'EOF'
hello\ world 
EOF

# Test standard input with multiple lines and special characters
test_stdin_special() {
  printf "%s\n" "hello" "world" "'single quotes'" '"double quotes"' '\back slash\' | ./shescapes
}
assert_out -d test_stdin_special <<'EOF'
hello world \'single\ quotes\' \"double\ quotes\" \\back\ slash\\ 
EOF

# Test with no input at all (should produce no output, not even a newline)
test_no_input() {
  printf "" | ./shescapes
}
assert_out -d test_no_input <<'EOF'
EOF

# Test with multiple file arguments
# Create temporary files
TEMP_FILE1=$(mktemp)
TEMP_FILE2=$(mktemp)
echo "file 1 line 1" > "$TEMP_FILE1"
echo "file 1 line 2" >> "$TEMP_FILE1"
echo "file 2 line 1" > "$TEMP_FILE2"

test_files() {
  ./shescapes "$TEMP_FILE1" "$TEMP_FILE2"
}
assert_out -d test_files <<'EOF'
file\ 1\ line\ 1 file\ 1\ line\ 2 file\ 2\ line\ 1 
EOF

# Test mixing files and stdin (using -)
test_mixed() {
  echo "stdin line" | ./shescapes "$TEMP_FILE1" - "$TEMP_FILE2"
}
assert_out -d test_mixed <<'EOF'
file\ 1\ line\ 1 file\ 1\ line\ 2 stdin\ line file\ 2\ line\ 1 
EOF

# Test non-existent file
test_nonexistent() {
  # We redirect stderr to stdout to capture the error message, but filter out
  # differences in shell vs cat error formatting.
  ./shescapes "$TEMP_FILE1" "does_not_exist" "$TEMP_FILE2" 2>&1 | sed -e 's/[^ ]*shescapes:.*does_not_exist.*/[error]/'
}
assert_out -d test_nonexistent <<'EOF'
file\ 1\ line\ 1 file\ 1\ line\ 2 [error]
file\ 2\ line\ 1 
EOF

# Cleanup temporary files
rm -f "$TEMP_FILE1" "$TEMP_FILE2"

done_testing
