#!/bin/bash
# Build and install tout to GOBIN.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run setup and installation in the script directory
(
  cd "$SCRIPT_DIR"
  ./0-setup.sh
  GOBIN_DIR="${GOBIN:-$(go env GOPATH)/bin}"
  mkdir -p "$GOBIN_DIR"
  go build -o "$GOBIN_DIR/tout" ./tout/cmd
)
