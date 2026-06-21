#!/bin/bash
# Tests for dconf-restore.
# Run from anywhere: bash misc/dconf-restore_test.bash

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")"; pwd)/dconf-restore"
FAKE_HOME='/home/testuser'
PASS=0
FAIL=0

# Run the script with a fake HOME so $HOME expansion is predictable.
run() { HOME="$FAKE_HOME" "$SCRIPT"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc"
    echo "  Expected: $(printf '%q' "$expected")"
    echo "  Actual:   $(printf '%q' "$actual")"
  fi
}

# Single-line helper: pipe one line through the script.
r1() { printf '%s\n' "$1" | run | tr -d '\r'; }

# ---------- Section headers pass through unchanged ----------
assert_eq "section header" \
  "[org/cinnamon/desktop/keybindings]" \
  "$(r1 "[org/cinnamon/desktop/keybindings]")"

assert_eq "root section header [/]" \
  "[/]" \
  "$(r1 "[/]")"

# ---------- Blank lines pass through ----------
assert_eq "blank line" \
  "" \
  "$(r1 "")"

# ---------- Key prefix stripping ----------
assert_eq "simple prefix stripped" \
  "custom-list=['custom9', 'custom8']" \
  "$(r1 "/org/cinnamon/desktop/keybindings@custom-list=['custom9', 'custom8']")"

assert_eq "deep subsection prefix stripped" \
  "binding=['<Primary><Alt>minus']" \
  "$(r1 "/org/cinnamon/desktop/keybindings/custom-keybindings/custom0@binding=['<Primary><Alt>minus']")"

assert_eq "GVariant @as [] value" \
  "my-key=@as []" \
  "$(r1 "/org/test@my-key=@as []")"

assert_eq "root-level key (@ with no path before it)" \
  "some-root-key='hello'" \
  "$(r1 "@some-root-key='hello'")"

assert_eq "value containing slashes" \
  "command='/home/testuser/cbin/1work'" \
  "$(r1 "/org/test@command='/home/testuser/cbin/1work'")"

assert_eq "key with hyphen" \
  "looking-glass-keybinding=@as []" \
  "$(r1 "/org/cinnamon/desktop/keybindings@looking-glass-keybinding=@as []")"

# ---------- $HOME expansion ----------
assert_eq "\$HOME/ expanded" \
  "command='/home/testuser/cbin/script'" \
  "$(r1 "/org/test@command='\$HOME/cbin/script'")"

assert_eq "exact \$HOME (no trailing slash) expanded" \
  "path='/home/testuser'" \
  "$(r1 "/org/test@path='\$HOME'")"

assert_eq "\$HOME in list expanded" \
  "list=['/home/testuser', '/home/testuser/sub']" \
  "$(r1 "/org/test@list=['\$HOME', '\$HOME/sub']")"

assert_eq "\$HOME not after single-quote is NOT expanded" \
  "other=\$HOME/thing" \
  "$(r1 "/org/test@other=\$HOME/thing")"

# ---------- -h flag ----------
assert_eq "-h prints help" \
  "See \`dconf-backup -h\` for more details." \
  "$("$SCRIPT" -h | tr -d '\r')"

# ---------- Multi-line round-trip ----------
MULTILINE_IN="[org/cinnamon/desktop/keybindings]
/org/cinnamon/desktop/keybindings@custom-list=['custom9', 'custom8']
/org/cinnamon/desktop/keybindings@looking-glass-keybinding=@as []

[org/cinnamon/desktop/keybindings/custom-keybindings/custom0]
/org/cinnamon/desktop/keybindings/custom-keybindings/custom0@binding=['<Primary><Alt>minus']
/org/cinnamon/desktop/keybindings/custom-keybindings/custom0@command='\$HOME/cbin/1work'
/org/cinnamon/desktop/keybindings/custom-keybindings/custom0@name='1work'"

MULTILINE_EXPECTED="[org/cinnamon/desktop/keybindings]
custom-list=['custom9', 'custom8']
looking-glass-keybinding=@as []

[org/cinnamon/desktop/keybindings/custom-keybindings/custom0]
binding=['<Primary><Alt>minus']
command='/home/testuser/cbin/1work'
name='1work'"

assert_eq "multi-line round-trip" \
  "$MULTILINE_EXPECTED" \
  "$(printf '%s\n' "$MULTILINE_IN" | run | tr -d '\r')"

# ---------- Summary ----------
echo
echo "Results: $PASS passed, $FAIL failed."
[[ $FAIL -eq 0 ]]
