#!/bin/bash
# Test for term (unified gnome-terminal launcher).
# Run this test script every time touching term.

. testutil.bash

cd "${0%/*}"
SCRIPT_DIR=$(pwd)

export TEST_TMP_DIR=$(mktemp -d -t term-test-XXXXXX)
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"
export DISPLAY=":99"
unset WAYLAND_DISPLAY

cp "$SCRIPT_DIR/term" "$TEST_TMP_DIR/term"
chmod +x "$TEST_TMP_DIR/term"

# Mock gnome-terminal: records args to $calls, records env to $env,
# and executes the command after '--' if present (so capture/stdin tests work).
cat > "$TEST_TMP_DIR/bin/gnome-terminal" <<EOF
#!/bin/bash
echo "ARGS: \$*" >> "$TEST_TMP_DIR/calls"
compgen -e | sort > "$TEST_TMP_DIR/env"
for ((i=1; i<=\$#; i++)); do
  if [[ "\${!i}" == "--" ]]; then
    shift \$i
    exec "\$@"
  fi
done
exit 0
EOF
chmod +x "$TEST_TMP_DIR/bin/gnome-terminal"

# Mock fzf: output the first line received on stdin
cat > "$TEST_TMP_DIR/bin/fzf" <<'EOF'
#!/bin/bash
head -n 1
EOF
chmod +x "$TEST_TMP_DIR/bin/fzf"

reset_files() {
  rm -f "$TEST_TMP_DIR/calls" "$TEST_TMP_DIR/env"
}

run_term() {
  (cd "$TEST_TMP_DIR" && ./term "$@")
}

# 1. Help option
assert "$TEST_TMP_DIR/term --help | grep -q 'Usage:'"

# 2. Shell mode: gnome-terminal called with --geometry; no 'bash -c'
reset_files
run_term --geometry=120x30
assert "grep -q 'ARGS: --geometry=120x30' '$TEST_TMP_DIR/calls'"
assert "! grep -q 'bash -c' '$TEST_TMP_DIR/calls'"

# 3. Shell mode: --clean is the default; non-essential vars are removed
export TERM_TEST_REMOVED="yes"
reset_files
run_term
assert "! grep -q '^TERM_TEST_REMOVED$' '$TEST_TMP_DIR/env'"
assert "grep -q '^DISPLAY$' '$TEST_TMP_DIR/env'"
assert "grep -q '^HOME$' '$TEST_TMP_DIR/env'"
assert "grep -q '^NEW_PWD$' '$TEST_TMP_DIR/env'"
unset TERM_TEST_REMOVED

# 4. Shell mode with --no-clean: env is preserved
export TERM_TEST_KEPT="yes"
reset_files
run_term --no-clean
assert "grep -q '^TERM_TEST_KEPT$' '$TEST_TMP_DIR/env'"
unset TERM_TEST_KEPT

# 5. Agent vars always unset, even with --no-clean
export ANTIGRAVITY_AGENT="1" CLAUDE_AGENT="1" IS_IN_AGENT="1"
reset_files
run_term --no-clean
assert "! grep -q '^ANTIGRAVITY_AGENT$' '$TEST_TMP_DIR/env'"
assert "! grep -q '^CLAUDE_AGENT$' '$TEST_TMP_DIR/env'"
assert "! grep -q '^IS_IN_AGENT$' '$TEST_TMP_DIR/env'"
unset ANTIGRAVITY_AGENT CLAUDE_AGENT IS_IN_AGENT

# 6. Command mode: gnome-terminal gets --wait, --hide-menubar, -t, and bash -c
reset_files
run_term echo hello
assert "grep -q -- '--wait' '$TEST_TMP_DIR/calls'"
assert "grep -q -- '--hide-menubar' '$TEST_TMP_DIR/calls'"
assert "grep -q -- '-t \*echo' '$TEST_TMP_DIR/calls'"
assert "grep -q 'bash -c' '$TEST_TMP_DIR/calls'"

# 7. Command mode: --capture captures stdout
reset_files
run_term --capture echo hello > "$TEST_TMP_DIR/capture_out"
assert "grep -q '^hello$' '$TEST_TMP_DIR/capture_out'"

# 8. Command mode: piped stdin is fed to the command, --capture returns output
reset_files
echo "piped_line" | run_term --capture fzf > "$TEST_TMP_DIR/stdin_out"
assert "grep -q '^piped_line$' '$TEST_TMP_DIR/stdin_out'"

# 9. Command mode: --wait appends "Press [ENTER]" to the inner command
reset_files
run_term --wait echo hello
assert "grep -q 'Press \[ENTER\]' '$TEST_TMP_DIR/calls'"

# 10. Command mode: --geometry is passed to gnome-terminal
reset_files
run_term --geometry=80x24 echo hello
assert "grep -q -- '--geometry=80x24' '$TEST_TMP_DIR/calls'"

# 11. Command mode: --title sets the window title
reset_files
run_term --title MyTool echo hello
assert "grep -q -- '-t \*MyTool' '$TEST_TMP_DIR/calls'"

# 12. Command mode: default is --no-clean; non-essential env vars survive
export TERM_TEST_CMD_KEPT="yes"
reset_files
run_term echo hello
assert "grep -q '^TERM_TEST_CMD_KEPT$' '$TEST_TMP_DIR/env'"
unset TERM_TEST_CMD_KEPT

# 13. Command mode with --clean: non-essential vars are removed
export TERM_TEST_CMD_REMOVED="yes"
reset_files
run_term --clean echo hello
assert "! grep -q '^TERM_TEST_CMD_REMOVED$' '$TEST_TMP_DIR/env'"
unset TERM_TEST_CMD_REMOVED

# 14. Error when DISPLAY is not set
DISPLAY="" WAYLAND_DISPLAY="" "$TEST_TMP_DIR/term" echo hello > "$TEST_TMP_DIR/disp_err" 2>&1
disp_rc=$?
assert '[[ $disp_rc -ne 0 ]]'
assert "grep -q 'DISPLAY' '$TEST_TMP_DIR/disp_err'"

done_testing
