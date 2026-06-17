#!/bin/bash
# Test for t (gnome-terminal environment isolator).
# Run this test script every time touching t.

. testutil.bash

# Move to the script parent directory
cd "${0%/*}"
SCRIPT_DIR=$(pwd)

# Setup temp directory for the test
export TEST_TMP_DIR=$(mktemp -d -t t-test-XXXXXX)
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

# Create a bin folder in the temp dir for mocks
mkdir -p "$TEST_TMP_DIR/bin"
export PATH="$TEST_TMP_DIR/bin:$PATH"

# Copy t to temp dir and create tt symlink
cp "$SCRIPT_DIR/t" "$TEST_TMP_DIR/t"
chmod +x "$TEST_TMP_DIR/t"
ln -sf t "$TEST_TMP_DIR/tt"

# Mock gnome-terminal
cat > "$TEST_TMP_DIR/bin/gnome-terminal" <<EOF
#!/bin/bash
# Print arguments to a file
echo "args: \$*" >> "$TEST_TMP_DIR/calls"
# Print environment variables to a file
compgen -e | sort > "$TEST_TMP_DIR/env"
EOF
chmod +x "$TEST_TMP_DIR/bin/gnome-terminal"

# Define test assertions
# 1. Test help option
assert "$TEST_TMP_DIR/t --help | grep -q 'Usage:'"

# 2. Test environment variable isolation and argument passing
# Set some environment variables:
export DISPLAY=":99"
export WAYLAND_DISPLAY="wayland-99"
export TEST_KEEP_VAR="not_a_kept_var" # this should be cleared
export TEST_WANTED_VAR_BUT_NOT_IN_WHITELIST="cleared_anyway"
export USER="testuser"
export HOME="/home/testuser"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export XDG_DATA_DIRS="/usr/share"
export GTK_MODULES="canberra-gtk-module"
export QT_IM_MODULE="ibus"
export LC_ALL="en_US.UTF-8"

# Run t with arguments
(
  cd "$TEST_TMP_DIR"
  ./t --geometry=80x24 --title="My Terminal"
)

# Assert arguments were passed to gnome-terminal
assert "grep -q 'args: --geometry=80x24 --title=My Terminal' '$TEST_TMP_DIR/calls'"

# 3. Test insertion of "--" before first non-flag argument
(
  cd "$TEST_TMP_DIR"
  ./t man fzf
)
assert "grep -F -q 'args: -- bash -c \"\$@\" t-wrapper man fzf' '$TEST_TMP_DIR/calls'"

# 4. Test no insertion of "--" if "--" is already present
(
  cd "$TEST_TMP_DIR"
  ./t --geometry=80x24 --title="My Terminal" -- man fzf
)
assert "grep -F -q 'args: --geometry=80x24 --title=My Terminal -- bash -c \"\$@\" t-wrapper man fzf' '$TEST_TMP_DIR/calls'"

# 5. Test option parsing with non-flag arguments
(
  cd "$TEST_TMP_DIR"
  ./t --geometry=80x24 --title="My Terminal" man fzf
)
assert "grep -F -q 'args: --geometry=80x24 --title=My Terminal -- bash -c \"\$@\" t-wrapper man fzf' '$TEST_TMP_DIR/calls'"

# 6. Test tt command wrapping with options and command
(
  cd "$TEST_TMP_DIR"
  ./tt --geometry=80x24 --title="My Terminal" man fzf
)
assert "grep -F -q 'args: --geometry=80x24 --title=My Terminal -- bash -c \"\$@\"; echo; echo \"Press [ENTER] to close the window\"; read t-wrapper man fzf' '$TEST_TMP_DIR/calls'"

# 7. Test tt command wrapping without options
(
  cd "$TEST_TMP_DIR"
  ./tt man fzf
)
assert "grep -F -q 'args: -- bash -c \"\$@\"; echo; echo \"Press [ENTER] to close the window\"; read t-wrapper man fzf' '$TEST_TMP_DIR/calls'"

# 8. Test tt command without command arguments (should open normal window without wrapping)
(
  cd "$TEST_TMP_DIR"
  ./tt
)
assert "grep -F -q 'args: ' '$TEST_TMP_DIR/calls'"




# Assert DISPLAY was kept
assert "grep -q '^DISPLAY$' '$TEST_TMP_DIR/env'"

# Assert USER was kept
assert "grep -q '^USER$' '$TEST_TMP_DIR/env'"

# Assert HOME was kept
assert "grep -q '^HOME$' '$TEST_TMP_DIR/env'"

# Assert glob variables (DBUS_*, XDG_*, GTK_*, QT_*, LC_*) were kept
assert "grep -q '^DBUS_SESSION_BUS_ADDRESS$' '$TEST_TMP_DIR/env'"
assert "grep -q '^XDG_DATA_DIRS$' '$TEST_TMP_DIR/env'"
assert "grep -q '^GTK_MODULES$' '$TEST_TMP_DIR/env'"
assert "grep -q '^QT_IM_MODULE$' '$TEST_TMP_DIR/env'"
assert "grep -q '^LC_ALL$' '$TEST_TMP_DIR/env'"

# Assert unwanted variables were cleared
assert "! grep -q '^TEST_KEEP_VAR$' '$TEST_TMP_DIR/env'"
assert "! grep -q '^TEST_WANTED_VAR_BUT_NOT_IN_WHITELIST$' '$TEST_TMP_DIR/env'"

done_testing
