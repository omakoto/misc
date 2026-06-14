#!/bin/bash
#
# rc-reload_test.bash - Tests for rc-reload.bash, specifically the
# _bash_is_idle helper that detects idle (subprocess-free) bash instances.
# Run from the misc/ directory: ./rc-reload_test.bash

. testutil.bash

# ---- Unit tests for _bash_is_idle ----

# Source only the helper; avoid sourcing the full rc-reload.bash which uses
# $() expansions that depend on a running makotorc environment.
_bash_is_idle() {
    local pid=$1
    local children=""
    if [[ -f "/proc/$pid/task/$pid/children" ]]; then
        read -r children < "/proc/$pid/task/$pid/children" 2>/dev/null
    else
        children=$(pgrep -P "$pid" 2>/dev/null)
    fi
    [[ -z "$children" ]]
}

# ---- Setup ----
# A named FIFO is used to keep "idle" subshells blocked (via bash builtin
# read, which has no child process) until cleanup.
TEST_FIFO=$(mktemp -u -t rc_reload_test_XXXXXX)
mkfifo "$TEST_FIFO"

_cleanup() {
    # Unblock FIFO-blocked subshells (up to N readers).
    # Writing to a FIFO blocks until a reader opens it, so write in background.
    # If a subshell has already exited, the orphaned write will fail once the
    # FIFO is removed.
    local p children
    for p in "$pid_idle" "$pid_busy" "$pid_temp"; do
        [[ -n "$p" ]] || continue
        # Kill the subshell's children (e.g. the background sleep 60)
        mapfile -t children < <(pgrep -P "$p" 2>/dev/null)
        kill -9 "${children[@]}" 2>/dev/null
    done
    # Unblock all three FIFO readers so the subshells exit naturally
    { echo done > "$TEST_FIFO"; } 2>/dev/null &
    { echo done > "$TEST_FIFO"; } 2>/dev/null &
    { echo done > "$TEST_FIFO"; } 2>/dev/null &
    # Give subshells a moment to unblock, then kill any still alive
    sleep 0.1
    kill -9 "$pid_idle" "$pid_busy" "$pid_temp" 2>/dev/null
    rm -f "$TEST_FIFO"
}
trap _cleanup EXIT

# ---- Helpers ----
#
# Key insight: bash's `read` builtin is NOT a child process, so a subshell
# blocked on `read < FIFO` appears idle (no children in /proc).
# We start subshells directly with & and capture $! immediately (not via $()
# which would create a subshell whose background jobs are its own children).

# ---- Test 1: process with no children is reported idle ----
# "read -r x < TEST_FIFO" blocks without spawning a child process.
# A trailing "; :" prevents bash's exec-optimization of the read builtin.
( read -r x < "$TEST_FIFO"; : ) &
pid_idle=$!
sleep 0.15  # let it settle

assert "_bash_is_idle $pid_idle"

# ---- Test 2: process with children is reported busy ----
# sleep 60 is a real child process; subshell also blocks on the FIFO.
( sleep 60 & read -r x < "$TEST_FIFO"; : ) &
pid_busy=$!
sleep 0.15

assert "! _bash_is_idle $pid_busy"

# ---- Test 3: once children finish, process becomes idle again ----
# Subshell spawns a very short-lived child (sleep 0.2), then blocks on FIFO.
( sleep 0.2 & read -r x < "$TEST_FIFO"; : ) &
pid_temp=$!
sleep 0.1  # sleep 0.2 still running

assert "! _bash_is_idle $pid_temp"

sleep 0.3  # sleep 0.2 has now exited; subshell still blocked on FIFO (idle)

assert "_bash_is_idle $pid_temp"

# ---- Test 4: non-existent PID is treated as idle (silently) ----
assert "_bash_is_idle 999999999"

done_testing
