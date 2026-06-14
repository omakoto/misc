#!/bin/bash
# Build and run grepgo.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run setup and build in the script directory (using a subshell to preserve original pwd)
(
  cd "$SCRIPT_DIR"
  ./000-setup.sh
  go build -o bin/grepgo ./grepgo/cmd
)

# Run the compiled binary using its absolute path (preserving original pwd for arguments)
exec "$SCRIPT_DIR/bin/grepgo" "$@"
