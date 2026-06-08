#!/bin/bash

# Unit tests for `misc/1` opener tool

if [[ "$0" == */* ]]; then
  DIR="${0%/*}"
else
  DIR="."
fi
. "$DIR/testutil.bash"

# Move to the script directory
cd "$DIR"

# Prevent GUI windows and use fallback `vi`
export DISPLAY=""
export WSL_DISTRO_NAME=""

# Silence the `ee` command printing to keep outputs clean
export EE_QUIET=1

# Create a temp directory for mock commands and test files
MOCK_DIR=$(mktemp -d)
trap "rm -rf $MOCK_DIR" EXIT

export PATH="$MOCK_DIR:$PATH"
export TEST_LOG="$MOCK_DIR/test.log"

# Helper to mock an executable
mock_cmd() {
  local cmd="$1"
  local log_content="${2:-0}"
  cat <<EOF > "$MOCK_DIR/$cmd"
#!/bin/bash
echo "[\$0] ARGS: \$*" >> "\$TEST_LOG"
if (( $log_content )) ; then
  for arg in "\$@"; do
    # Log contents of any temp files to verify content writing (like pipes/gz/deb list/hexdump)
    if [[ "\$arg" =~ ^/ && -f "\$arg" ]]; then
      echo "FILE_CONTENT(\$arg):" >> "\$TEST_LOG"
      cat "\$arg" >> "\$TEST_LOG"
    fi
  done
fi
EOF
  chmod +x "$MOCK_DIR/$cmd"
}

# Create mocks for external tools executed by `1`
mock_cmd vi 1
mock_cmd c 1
mock_cmd xml-pretty
mock_cmd json_pp
mock_cmd hd
mock_cmd zcat
mock_cmd dpkg
mock_cmd pandoc
mock_cmd sqliteman

# Mock `istext` command so it identifies text/binary files properly for tests
cat <<'EOF' > "$MOCK_DIR/istext"
#!/bin/bash
if [[ "$1" == *.bin || "$1" == *.deb || "$1" == *.db || "$1" == *.gz ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_DIR/istext"

# Create helper dummy files to test
touch "$MOCK_DIR/test.txt"
touch "$MOCK_DIR/test.xml"
touch "$MOCK_DIR/test.json"
touch "$MOCK_DIR/test.bin"
touch "$MOCK_DIR/test.gz"
touch "$MOCK_DIR/test.deb"
touch "$MOCK_DIR/test.md"
touch "$MOCK_DIR/test.db"

# A test runner function to execute `./1` and print the normalized mock log
run_1() {
  > "$TEST_LOG"
  ./1 "$@" >/dev/null 2>&1
  sleep 0.1
  
  # Normalize paths and PIDs in output log
  cat "$TEST_LOG" | \
    sed -E \
        -e 's![[:space:]]+$!!g' \
        -e "s!$MOCK_DIR/![temp]/!g" \
        -e "s!$MOCK_DIR![temp]!g" \
        -e "s!${PIPE_TEMP:-/tmp}/![tmp]/!g" \
        -e "s!/tmp/![tmp]/!g" \
        -e 's/-[0-9]+-pretty/-[pid]-pretty/g' \
        -e 's/-[0-9]+-zcat/-[pid]-zcat/g' \
        -e 's/-[0-9]+-list/-[pid]-list/g' \
        -e 's/-[0-9]+-hexdump/-[pid]-hexdump/g' \
        -e 's/-[0-9]+\.html/-[pid].html/g' \
        -e 's/pipe-[0-9]+-[0-9]+-[0-9]+/pipe-[date]-[pid]/g'
}

run_1_stdin() {
  > "$TEST_LOG"
  echo "hello pipe" | ./1 "$@" >/dev/null 2>&1
  
  # Normalize paths and PIDs in output log
  cat "$TEST_LOG" | \
    sed -E \
        -e 's![[:space:]]+$!!g' \
        -e "s!$MOCK_DIR/![temp]/!g" \
        -e "s!$MOCK_DIR![temp]!g" \
        -e "s!${PIPE_TEMP:-/tmp}/![tmp]/!g" \
        -e "s!/tmp/![tmp]/!g" \
        -e 's/-[0-9]+-pretty/-[pid]-pretty/g' \
        -e 's/-[0-9]+-zcat/-[pid]-zcat/g' \
        -e 's/-[0-9]+-list/-[pid]-list/g' \
        -e 's/-[0-9]+-hexdump/-[pid]-hexdump/g' \
        -e 's/-[0-9]+\.html/-[pid].html/g' \
        -e 's/pipe-[0-9]+-[0-9]+-[0-9]+/pipe-[date]-[pid]/g'
}

# --- Test Cases ---

# 1. Basic text file opening (should invoke vi)
assert_out -d run_1 "$MOCK_DIR/test.txt" <<'EOF'
[[temp]/vi] ARGS: [temp]/test.txt
FILE_CONTENT([temp]/test.txt):
EOF

# 2. Text file opening at a specific line (-l flag)
assert_out -d run_1 -l 42 "$MOCK_DIR/test.txt" <<'EOF'
[[temp]/vi] ARGS: +42 [temp]/test.txt
FILE_CONTENT([temp]/test.txt):
EOF

# 3. XML file pretty print with -p flag
assert_out -d run_1 -p "$MOCK_DIR/test.xml" <<'EOF'
[[temp]/xml-pretty] ARGS:
[[temp]/vi] ARGS: [tmp]/test.xml-[pid]-pretty.xml
FILE_CONTENT([tmp]/test.xml-[pid]-pretty.xml):
EOF

# 4. JSON file pretty print with -p flag
assert_out -d run_1 -p "$MOCK_DIR/test.json" <<'EOF'
[[temp]/json_pp] ARGS:
[[temp]/vi] ARGS: [tmp]/test.json-[pid]-pretty.json
FILE_CONTENT([tmp]/test.json-[pid]-pretty.json):
EOF

# 5. Binary file opening (falls back to hexdump)
assert_out -d run_1 "$MOCK_DIR/test.bin" <<'EOF'
[[temp]/hd] ARGS: [temp]/test.bin
[[temp]/vi] ARGS: [tmp]/test.bin-[pid]-hexdump.txt
FILE_CONTENT([tmp]/test.bin-[pid]-hexdump.txt):
EOF

# 6. Compressed .gz file (decompresses using zcat)
assert_out -d run_1 "$MOCK_DIR/test.gz" <<'EOF'
[[temp]/zcat] ARGS: [temp]/test.gz
[[temp]/vi] ARGS: [tmp]/test.gz-[pid]-zcat.txt
FILE_CONTENT([tmp]/test.gz-[pid]-zcat.txt):
EOF

# 7. Deb package file (lists files using dpkg -c)
assert_out -d run_1 "$MOCK_DIR/test.deb" <<'EOF'
[[temp]/dpkg] ARGS: -c [temp]/test.deb
[[temp]/vi] ARGS: [tmp]/test.deb-[pid]-list.txt
FILE_CONTENT([tmp]/test.deb-[pid]-list.txt):
EOF

# 8. Markdown file (renders with pandoc and opens HTML via 'c')
assert_out -d run_1 "$MOCK_DIR/test.md" <<'EOF'
[[temp]/pandoc] ARGS: -f gfm -s -V maxwidth=min(95%, 120em) [temp]/test.md -o [tmp]/test.md-[pid].html
[[temp]/c] ARGS: [tmp]/test.md-[pid].html
EOF

# 9. SQLite DB file (opens with sqliteman in bg)
assert_out -d run_1 "$MOCK_DIR/test.db" <<'EOF'
[[temp]/sqliteman] ARGS: [temp]/test.db
EOF

# 10. Pipeline/stdin input
assert_out -d run_1_stdin -z --stdin <<'EOF'
[[temp]/vi] ARGS: [tmp]/pipe-[date]-[pid].log
FILE_CONTENT([tmp]/pipe-[date]-[pid].log):
hello pipe
EOF

done_testing
