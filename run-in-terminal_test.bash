#!/bin/bash
# Test script for run-in-terminal.
# Verifies options (help, title, geometry), GUI path (gnome-terminal execution), and non-GUI fallback.
# Run this test script every time modifying run-in-terminal.

set -e

print_help() {
  cat <<'EOF'
run-in-terminal_test.bash - Test suite for run-in-terminal

Usage:
  run-in-terminal_test.bash [options]

Options:
  -h, --help Show this help message.
EOF
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  print_help
  exit 0
fi

# Locate target script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TARGET="$DIR/run-in-terminal"

# Set up test environment with a temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_BIN_DIR="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"

# Create mock fzf: outputs the first line it receives from stdin
MOCK_FZF="$MOCK_BIN_DIR/fzf"
cat > "$MOCK_FZF" <<'EOF'
#!/bin/bash
echo "mock_fzf_called_with: $@" >&2
head -n 1
EOF
chmod +x "$MOCK_FZF"

# Create mock gnome-terminal: parses args, verifies geometry, and runs the command after '--' directly
MOCK_TERM="$MOCK_BIN_DIR/gnome-terminal"
cat > "$MOCK_TERM" <<'EOF'
#!/bin/bash
args=("$@")
# verify --wait is present
wait_present=0
geometry_value=""
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "--wait" ]]; then
    wait_present=1
  fi
  if [[ "${args[i]}" == "--geometry" ]]; then
    geometry_value="${args[i+1]}"
  fi
  if [[ "${args[i]}" == --geometry=* ]]; then
    geometry_value="${args[i]#--geometry=}"
  fi
done

if (( ! wait_present )); then
  echo "FAIL: gnome-terminal was not called with --wait" >&2
  exit 1
fi

echo "mock_terminal_geometry: $geometry_value" >&2

# Locate '--' and execute the command following it
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "--" ]]; then
    echo "mock_terminal_command: ${args[@]:i+1}" >&2
    exec "${args[@]:i+1}"
  fi
done
echo "FAIL: '--' not found in mock gnome-terminal args" >&2
exit 1
EOF
chmod +x "$MOCK_TERM"

# Create mock isx: defaults to true (simulating running X session)
MOCK_ISX="$MOCK_BIN_DIR/isx"
cat > "$MOCK_ISX" <<'EOF'
#!/bin/bash
exit ${MOCK_ISX_EXIT:-0}
EOF
chmod +x "$MOCK_ISX"

# Add mock bin to PATH
export PATH="$MOCK_BIN_DIR:$PATH"

# Test 1: Help message
echo "Running Test 1: Help message check..."
out=$("$TARGET" --help)
if [[ "$out" != *"Usage:"* ]]; then
  echo "FAIL: Expected help message containing 'Usage:', got:"
  echo "$out"
  exit 1
fi
echo "Test 1 passed!"

# Test 2: Piped input with X session (GUI path) and custom title/geometry, capturing stdout
echo "Running Test 2: Piped input with GUI session, custom title and geometry with capture (-c)..."
export MOCK_ISX_EXIT=0
err_capture=$(mktemp)
out=$(echo -e "selection1\nselection2" | "$TARGET" --title "CustomTitle" --geometry "120x40" -c -- fzf --multi 2>"$err_capture")
err_content=$(cat "$err_capture")
rm -f "$err_capture"

if [[ "$out" != "selection1" ]]; then
  echo "FAIL: Expected output 'selection1', got '$out'"
  exit 1
fi
if [[ "$err_content" != *"mock_terminal_geometry: 120x40"* ]]; then
  echo "FAIL: Expected terminal geometry '120x40', got stderr:"
  echo "$err_content"
  exit 1
fi
if [[ "$err_content" != *"mock_fzf_called_with: --multi"* ]]; then
  echo "FAIL: Expected mock fzf to be called with --multi, got stderr:"
  echo "$err_content"
  exit 1
fi
echo "Test 2 passed!"

# Test 3: Fallback path (isx=false) with capture (-c)
echo "Running Test 3: Fallback path execution (isx=false) with capture (-c)..."
export MOCK_ISX_EXIT=1
out=$(echo -e "fallback_selection\nline2" | "$TARGET" -c -- fzf)
if [[ "$out" != "fallback_selection" ]]; then
  echo "FAIL: Expected output 'fallback_selection', got '$out'"
  exit 1
fi
echo "Test 3 passed!"

# Test 4: Missing command error
echo "Running Test 4: Missing command check..."
if "$TARGET" --title "NoCommand" >/dev/null 2>/dev/null; then
  echo "FAIL: Expected exit code > 0 when running with no command"
  exit 1
fi
echo "Test 4 passed!"

# Test 5: Verify no capture when -c is omitted
echo "Running Test 5: Verify no capture when -c is omitted..."
export MOCK_ISX_EXIT=0
err_capture=$(mktemp)
"$TARGET" --title "TestNoCapture" -- echo "hello" 2>"$err_capture" || true
err_content=$(cat "$err_capture")
rm -f "$err_capture"

if [[ "$err_content" == *"> /tmp/run_in_terminal_output"* ]]; then
  echo "FAIL: Expected no redirection to temp output file, but stderr contained:"
  echo "$err_content"
  exit 1
fi
echo "Test 5 passed!"

# Test 6: Verify optional '--' when omitted
echo "Running Test 6: Verify optional '--' when omitted..."
export MOCK_ISX_EXIT=0
err_capture=$(mktemp)
"$TARGET" --title "TestOptional" -c fzf --multi < /dev/null >/dev/null 2>"$err_capture" || true
err_content=$(cat "$err_capture")
rm -f "$err_capture"

if [[ "$err_content" != *"mock_fzf_called_with: --multi"* ]]; then
  echo "FAIL: Expected mock fzf to be called with --multi, but stderr was:"
  echo "$err_content"
  exit 1
fi
echo "Test 6 passed!"

echo "All tests passed successfully!"
exit 0

