#!/bin/bash
#
# fzf-select-window_test.bash - Tests for fzf-select-window.
# Run from the misc/ directory: ./fzf-select-window_test.bash
#

. testutil.bash

# Create temp mock directory and set HOME to isolate common_rc loading
export MOCK_DIR=$(mktemp -d -t fzf-select-window-test-XXXXXX)
trap 'rm -rf "$MOCK_DIR"' EXIT

export HOME="$MOCK_DIR"
mkdir -p "$MOCK_DIR/cbin"
# Symlink misc so colors.bash can be resolved under mock HOME
ln -s /home/omakoto/cbin/misc "$MOCK_DIR/cbin/misc"
touch "$MOCK_DIR/cbin/common_rc"

cat > "$MOCK_DIR/mock-gnome-list-windows" <<EOF
#!/bin/bash
cat <<'JSON'
{"id": 111, "pid": 1234, "wm_class": "code", "cwd": "$HOME/cbin", "comm": "code", "title": "VS Code"}
{"id": 222, "pid": 5678, "wm_class": "terminal", "cwd": "/android/main/frameworks/base", "comm": "bash", "title": "Terminal"}
{"id": 333, "pid": 9999, "wm_class": "browser", "cwd": "?", "comm": "chrome", "title": "Browser"}
JSON
EOF
chmod +x "$MOCK_DIR/mock-gnome-list-windows"

# Mock fzf (saves stdin, prints environment and arguments to stderr, and returns the second line containing "Terminal")
cat > "$MOCK_DIR/mock-fzf" <<'EOF'
#!/bin/bash
tee "$MOCK_DIR/fzf_input" >/dev/null
echo "fzf env FZF_DEFAULT_OPTS: $FZF_DEFAULT_OPTS" >&2
echo "fzf args: $*" >&2
cat "$MOCK_DIR/fzf_input" | grep "Terminal"
EOF
chmod +x "$MOCK_DIR/mock-fzf"

# Mock gdbus (prints to stderr since fzf-select-window redirects stdout of gdbus to /dev/null)
cat > "$MOCK_DIR/mock-gdbus" <<'EOF'
#!/bin/bash
echo "gdbus call: $*" >&2
EOF
chmod +x "$MOCK_DIR/mock-gdbus"

# Export variables for fzf-select-window overrides
export GNOME_LIST_WINDOWS="$MOCK_DIR/mock-gnome-list-windows"
export FZF="$MOCK_DIR/mock-fzf"
export GDBUS="$MOCK_DIR/mock-gdbus"

# Test 1: Verify output, fzf arguments, and gdbus call for normal execution
actual_output() {
  # Force a header into FZF_DEFAULT_OPTS
  export FZF_DEFAULT_OPTS="--header 'My Custom Header' --layout=reverse"
  
  local out
  out=$(./fzf-select-window 2>&1)
  
  # Check that --header is stripped from FZF_DEFAULT_OPTS
  if echo "$out" | grep -F "fzf env FZF_DEFAULT_OPTS:" | grep -q "\-\-header"; then
    echo "FAIL: --header was not stripped from FZF_DEFAULT_OPTS. Got: $out"
    return 1
  fi
  
  # Check that other options (like --layout=reverse) are kept
  if ! echo "$out" | grep -F "fzf env FZF_DEFAULT_OPTS:" | grep -q "\-\-layout=reverse"; then
    echo "FAIL: other FZF_DEFAULT_OPTS options were not preserved. Got: $out"
    return 1
  fi
  
  # Check that gdbus call is correct
  if ! echo "$out" | grep -q "gdbus call:.*Activate uint32 222"; then
    echo "FAIL: gdbus Activate call not found or incorrect. Got: $out"
    return 1
  fi
  
  # Check fzf arguments
  if ! echo "$out" | grep -q "fzf args:.*--with-nth=2.."; then
    echo "FAIL: fzf args incorrect. Got: $out"
    return 1
  fi

  # Check that fzf input contains bold-yellow bash and correct order/formatting
  local expected_line
  expected_line=$(printf "222\t\e[1;33m[bash]\e[0m              Terminal                                \t\e[36m# /a/m/f/b/\e[0m")
  if ! grep -F -q "$expected_line" "$MOCK_DIR/fzf_input"; then
    echo "FAIL: fzf input formatting incorrect. Expected line containing '$expected_line', got:"
    cat "$MOCK_DIR/fzf_input"
    return 1
  fi

  echo "PASS: fzf-select-window normal execution"
}
assert_out -d actual_output <<'EOF'
PASS: fzf-select-window normal execution
EOF

# Test 2: Test help command option
actual_output() {
  ./fzf-select-window --help | head -n 1
}
assert_out -d actual_output <<'EOF'
fzf-select-window - Select and activate a GNOME Shell window using fzf.
EOF

# Test 3: Test invalid arguments
actual_output() {
  ./fzf-select-window invalid-arg 2>&1 | head -n 1
}
assert_out -d actual_output <<'EOF'
fzf-select-window: Unknown option or argument: invalid-arg
EOF

done_testing
