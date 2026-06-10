#!/bin/bash
# Test runner wrapper for git-meld-history.bash.
# Runs the integration test suite in git-meld-history_test.bash targeting git-meld-history.bash.

export TARGET_SCRIPT="git-meld-history.bash"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/git-meld-history_test.bash"
