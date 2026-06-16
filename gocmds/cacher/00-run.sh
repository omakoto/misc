#!/bin/bash
# Build and run cacher.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run setup and build in the script directory (using a subshell to preserve original pwd)
(
  cd "$SCRIPT_DIR"
  ./0-setup.sh
  go build -o bin/cacher ./cacher/cmd
)

# Run the compiled binary using its absolute path (preserving original pwd for arguments)
exec "$SCRIPT_DIR/bin/cacher" "$@"
