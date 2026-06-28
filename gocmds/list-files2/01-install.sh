#!/bin/bash
# Build and install list-files2 to GOBIN.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run setup and installation in the script directory
(
  cd "$SCRIPT_DIR"
  ./0-setup.sh
  go install ./list-files2/cmd
)
