#!/bin/bash
# integration_test.sh - Integration test suite for list-files CLI.

set -euo pipefail

# Get the project root directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PROJECT_DIR/bin/list-files"

# 1. Compile the binary if not present
(
  cd "$PROJECT_DIR"
  ./0-setup.sh
  go build -o bin/list-files ./list-files/cmd/list-files
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

# Test Default ./ stripping (running with . as argument)
echo "Running test: Strip start dir (default)"
actual_strip=$(cd "$TEMP_DIR" && "$BIN" | paste -sd, -)
expected_strip="a/x.txt,b/y.txt,c.txt,d/e/z.txt"
if [[ "$actual_strip" != "$expected_strip" ]]; then
  echo "FAIL: Default strip start dir"
  echo "  Expected: $expected_strip"
  echo "  Got:      $actual_strip"
  exit 1
fi

# Test --no-strip-start-dir
echo "Running test: No strip start dir"
actual_no_strip=$(cd "$TEMP_DIR" && "$BIN" --no-strip-start-dir | paste -sd, -)
expected_no_strip="./a/x.txt,./b/y.txt,./c.txt,./d/e/z.txt"
if [[ "$actual_no_strip" != "$expected_no_strip" ]]; then
  echo "FAIL: --no-strip-start-dir"
  echo "  Expected: $expected_no_strip"
  echo "  Got:      $actual_no_strip"
  exit 1
fi

# Test --show-fullpath / -F
echo "Running test: Show fullpath"
home_dir="$HOME"
abs_a="${TEMP_DIR}/a/x.txt"
abs_b="${TEMP_DIR}/b/y.txt"
abs_c="${TEMP_DIR}/c.txt"
abs_d="${TEMP_DIR}/d/e/z.txt"
tild_a="${abs_a/#$home_dir/\~}"
tild_b="${abs_b/#$home_dir/\~}"
tild_c="${abs_c/#$home_dir/\~}"
tild_d="${abs_d/#$home_dir/\~}"
expected_fullpath="a/x.txt,$tild_a,b/y.txt,$tild_b,c.txt,$tild_c,d/e/z.txt,$tild_d"

actual_fullpath=$(cd "$TEMP_DIR" && "$BIN" -F | paste -sd, -)
if [[ "$actual_fullpath" != "$expected_fullpath" ]]; then
  echo "FAIL: Show fullpath (-F)"
  echo "  Expected: $expected_fullpath"
  echo "  Got:      $actual_fullpath"
  exit 1
fi

# Test --no-home-tild
echo "Running test: No home tild"
expected_no_tild="a/x.txt,$abs_a,b/y.txt,$abs_b,c.txt,$abs_c,d/e/z.txt,$abs_d"
actual_no_tild=$(cd "$TEMP_DIR" && "$BIN" -F --no-home-tild | paste -sd, -)
if [[ "$actual_no_tild" != "$expected_no_tild" ]]; then
  echo "FAIL: --no-home-tild"
  echo "  Expected: $expected_no_tild"
  echo "  Got:      $actual_no_tild"
  exit 1
fi

# Test --no-show-relative-path / -R
echo "Running test: No show relative path"
expected_no_rel="$tild_a,$tild_b,$tild_c,$tild_d"
actual_no_rel=$(cd "$TEMP_DIR" && "$BIN" -F --no-show-relative-path | paste -sd, -)
if [[ "$actual_no_rel" != "$expected_no_rel" ]]; then
  echo "FAIL: --no-show-relative-path"
  echo "  Expected: $expected_no_rel"
  echo "  Got:      $actual_no_rel"
  exit 1
fi

# Test Broken pipe handling
echo "Running test: Broken pipe"
"$BIN" -d "$TEMP_DIR" | head -n 2 > /dev/null
exit_code=${PIPESTATUS[0]}
if [[ $exit_code -ne 0 ]]; then
  echo "FAIL: Broken pipe exit code was $exit_code, expected 0"
  exit 1
fi

echo "ALL INTEGRATION TESTS PASSED!"
