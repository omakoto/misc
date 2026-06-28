#!/bin/bash
# integration_test.sh - Integration test suite for list-files2 CLI.

set -euo pipefail

# Get the project root directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PROJECT_DIR/bin/list-files2"

# 1. Compile the binary if not present
(
  cd "$PROJECT_DIR"
  ./0-setup.sh
  go build -o bin/list-files2 ./list-files2/cmd
)

# 2. Setup temporary directory for tests
TEMP_DIR=$(mktemp -d)
defer() {
  rm -rf "$TEMP_DIR"
}
trap defer EXIT

mkdir -p "$TEMP_DIR"/.git
mkdir -p "$TEMP_DIR"/a
mkdir -p "$TEMP_DIR"/b
mkdir -p "$TEMP_DIR"/d/e

echo "config" > "$TEMP_DIR"/.git/config
echo "a/x" > "$TEMP_DIR"/a/x.txt
echo "b/y" > "$TEMP_DIR"/b/y.txt
echo "c" > "$TEMP_DIR"/c.txt
echo "d/e/z" > "$TEMP_DIR"/d/e/z.txt

# Helper to run and compare stdout
assert_output() {
  local label="$1"
  local expected="$2"
  shift 2
  echo "Running test: $label"
  local actual
  actual=$("$BIN" "$@" | sed "s|$TEMP_DIR/||g" | paste -sd, -)
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label"
    echo "  Expected: $expected"
    echo "  Got:      $actual"
    exit 1
  fi
}

# Test Help
echo "Running test: Help"
"$BIN" -h > /dev/null

# Test Default options (no options)
assert_output "Default options" "a/x.txt,b/y.txt,c.txt,d/e/z.txt" "$TEMP_DIR"

# Test --reverse / -r
assert_output "Reverse" "d/e/z.txt,c.txt,b/y.txt,a/x.txt" -r "$TEMP_DIR"

# Test --show-directories / -d
assert_output "Show directories" ",a/,a/x.txt,b/,b/y.txt,c.txt,d/,d/e/,d/e/z.txt" -d "$TEMP_DIR"

# Test --max-files / -n
assert_output "Max files" ",a/,a/x.txt,b/" -d -n 4 "$TEMP_DIR"

# Test --show-all / -a
assert_output "Show all" ".git/config,a/x.txt,b/y.txt,c.txt,d/e/z.txt" -a "$TEMP_DIR"

# Test --para / -j
assert_output "Parallel 1" "a/x.txt,b/y.txt,c.txt,d/e/z.txt" -j 1 "$TEMP_DIR"
assert_output "Parallel 10" "a/x.txt,b/y.txt,c.txt,d/e/z.txt" -j 10 "$TEMP_DIR"

# Test --max-depth / -m
assert_output "Max depth 0" "" -d -m 0 "$TEMP_DIR"
assert_output "Max depth 1" ",a/,b/,c.txt,d/" -d -m 1 "$TEMP_DIR"
assert_output "Max depth 2" ",a/,a/x.txt,b/,b/y.txt,c.txt,d/,d/e/" -d -m 2 "$TEMP_DIR"

# Test Broken pipe handling
echo "Running test: Broken pipe"
"$BIN" -d "$TEMP_DIR" | head -n 2 > /dev/null
exit_code=${PIPESTATUS[0]}
if [[ $exit_code -ne 0 ]]; then
  echo "FAIL: Broken pipe exit code was $exit_code, expected 0"
  exit 1
fi

echo "ALL INTEGRATION TESTS PASSED!"
