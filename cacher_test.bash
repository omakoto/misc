#!/bin/bash
#
# cacher_test.bash - Integration test suite for cacher.
# Run this test script to verify cacher functionality.
#

. testutil.bash

# Temporary directory for tests
TEST_DIR=$(mktemp -d -t cacher_test_XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

CACHE_FILE="$TEST_DIR/cache.txt"
LOCK_FILE="$TEST_DIR/cache.lock"

# Helper to clear files
clear_files() {
  rm -f "$CACHE_FILE" "$LOCK_FILE" "${CACHE_FILE}.tmp"
}

# Test 1: Help message
assert "./cacher -h 2>&1 | grep -q 'Cache command stdout'"
assert "./cacher --help 2>&1 | grep -q 'Cache command stdout'"

# Test 2: First run with default text
clear_files
# Run cacher. It should:
# 1. Immediately return "default_val"
# 2. Start the command (which sleeps 1 then prints "new_val") in background
echo -n "default_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n new_val" -f "$CACHE_FILE" -d "default_val"

# Verify that the cache file has been created and initially has "default_val"
[[ -f "$CACHE_FILE" ]] || fail "Cache file not created on first run"
assert "[[ \$(cat '$CACHE_FILE') == 'default_val' ]]"

# Wait for background command to finish and update cache
sleep 1.5
assert "[[ \$(cat '$CACHE_FILE') == 'new_val' ]]"


# Test 2b: First run with omitted default text (should default to "?")
clear_files
# Run cacher without -d. It should return "?" immediately
echo -n "?" | assert_out -d -- ./cacher -c "sleep 1 && echo -n new_val" -f "$CACHE_FILE"

# Verify that the cache file has been created and initially has "?"
[[ -f "$CACHE_FILE" ]] || fail "Cache file not created on first run with default '?'"
assert "[[ \$(cat '$CACHE_FILE') == '?' ]]"

# Wait for background command to finish and update cache
sleep 1.5
assert "[[ \$(cat '$CACHE_FILE') == 'new_val' ]]"


# Test 3: Fresh Cache
# Set max-age to 10 seconds. Since it is only a few seconds old, it is fresh.
# It should output the cached content ("new_val") and NOT trigger the command.
# We run a command that writes "newer_val" if it runs, but it shouldn't run.
clear_files
echo -n "cached_val" > "$CACHE_FILE"
echo -n "cached_val" | assert_out -d -- ./cacher -c "echo -n newer_val" -f "$CACHE_FILE" -a 10
sleep 0.5
assert "[[ \$(cat '$CACHE_FILE') == 'cached_val' ]]"


# Test 4: Stale Cache
# Since max-age is 0, the cache is instantly stale.
# It should immediately print "cached_val", and spawn the command in background.
clear_files
echo -n "cached_val" > "$CACHE_FILE"
echo -n "cached_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n updated_val" -f "$CACHE_FILE" -a 0
# Verify it initially still has "cached_val"
assert "[[ \$(cat '$CACHE_FILE') == 'cached_val' ]]"
sleep 1.5
# Verify it now has "updated_val"
assert "[[ \$(cat '$CACHE_FILE') == 'updated_val' ]]"


# Test 5: Double Run prevention (lock file)
# If a BG process is already running, a new run should return the cache value and exit immediately
# without waiting or starting another process.
clear_files
echo -n "init_val" > "$CACHE_FILE"

# Start a BG command that takes 2 seconds and updates to "first_bg"
./cacher -c "sleep 2 && echo -n first_bg" -f "$CACHE_FILE" -a 0 &
# Wait a bit to let it acquire the lock and start running
sleep 0.5

# Now run a second cacher with command to update to "second_bg"
# It should print "init_val" (since lock is held, it won't run "second_bg")
echo -n "init_val" | assert_out -d -- ./cacher -c "sleep 2 && echo -n second_bg" -f "$CACHE_FILE" -a 0

# Wait for the first command to finish
sleep 2.0
# The cache should be "first_bg", not "second_bg"
assert "[[ \$(cat '$CACHE_FILE') == 'first_bg' ]]"


# Test 6: Verbose logging
clear_files
VERBOSE_LOG="$TEST_DIR/verbose.log"
# Run cacher with -v, capturing stderr
./cacher -c "echo -n new_val" -f "$CACHE_FILE" -v 2> "$VERBOSE_LOG"
assert "grep -q 'Checking lock file' '$VERBOSE_LOG'"
assert "grep -q 'First run detected' '$VERBOSE_LOG'"
assert "grep -q 'Starting background command' '$VERBOSE_LOG'"


# Test 7: Timeout / Auto-kill of stale process
clear_files
echo -n "init_val" > "$CACHE_FILE"

# Start a BG command that takes 10 seconds
./cacher -c "sleep 10 && echo -n long_bg" -f "$CACHE_FILE" -a 0 &
sleep 0.5

# Run a second cacher with timeout 0 (instant timeout)
# It should detect the stale process group, kill it, and start the new command in background.
# Output should be the old cached value ("init_val") immediately
echo -n "init_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n new_bg" -f "$CACHE_FILE" -a 0 -t 0

# Wait for the new background command to finish
sleep 1.5
# Check if the cache has been updated to "new_bg" (shows the 10-second one was killed and new one completed)
assert "[[ \$(cat '$CACHE_FILE') == 'new_bg' ]]"


# Test 8: --show-stderr redirection
clear_files
STDERR_OUT="$TEST_DIR/stderr.log"
# The command prints to stderr, wait 0.5s so it runs in background and prints it.
./cacher -c "echo -n command_error >&2" -f "$CACHE_FILE" --show-stderr 2> "$STDERR_OUT"
sleep 0.5
assert "grep -q 'command_error' '$STDERR_OUT'"


# Test 9: --force runs BG command even if cache is fresh
clear_files
echo -n "fresh_val" > "$CACHE_FILE"
# Run with max-age 100 (cache is fresh), but with -F.
# It should output "fresh_val" immediately, and start BG command to refresh it.
echo -n "fresh_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n forced_fresh" -f "$CACHE_FILE" -a 100 -F
# Wait for the BG command to complete
sleep 1.5
assert "[[ \$(cat '$CACHE_FILE') == 'forced_fresh' ]]"


# Test 10: --force kills currently running process group without timeout limit
clear_files
echo -n "init_val" > "$CACHE_FILE"
# Start a long-running BG process
./cacher -c "sleep 10 && echo -n long_bg" -f "$CACHE_FILE" -a 0 &
sleep 0.5
# Run second process with --force. It should output "init_val", kill the first, and start the new one.
echo -n "init_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n forced_bg" -f "$CACHE_FILE" -a 0 --force
# Wait for the new BG process to complete
sleep 1.5
assert "[[ \$(cat '$CACHE_FILE') == 'forced_bg' ]]"


# Test 11: --foreground option runs in foreground and outputs new result directly
clear_files
# Run cacher in foreground mode. It should block for 1 second and then output "foreground_val"
# directly to stdout.
echo -n "foreground_val" | assert_out -d -- ./cacher -c "sleep 1 && echo -n foreground_val" -f "$CACHE_FILE" -g
# Cache file must have been updated immediately
assert "[[ \$(cat '$CACHE_FILE') == 'foreground_val' ]]"


# Test 12: --foreground kills currently running background process
clear_files
echo -n "init_val" > "$CACHE_FILE"
# Start a long-running background command
./cacher -c "sleep 10 && echo -n long_bg" -f "$CACHE_FILE" -a 0 &
sleep 0.5
# Run in foreground. It should kill the long-running background job, run the new command,
# and output the new value when done.
echo -n "foreground_killed_bg" | assert_out -d -- ./cacher -c "sleep 1 && echo -n foreground_killed_bg" -f "$CACHE_FILE" -g
assert "[[ \$(cat '$CACHE_FILE') == 'foreground_killed_bg' ]]"


done_testing
