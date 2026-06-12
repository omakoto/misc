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


done_testing
