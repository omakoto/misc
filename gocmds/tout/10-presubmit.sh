#!/bin/bash
# Run presubmit checks for tout: formatting, vetting, static analysis, and unit tests.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Switch to the script directory for checks
cd "$SCRIPT_DIR"

# Ensure setup is run
./0-setup.sh

echo "==> Running gofmt..."
gofmt -s -w .

echo "==> Running go vet..."
go vet ./...

if [[ -n "$(command -v staticcheck 2>/dev/null)" ]]; then
  echo "==> Running staticcheck..."
  staticcheck ./...
else
  echo "==> staticcheck not found, skipping."
fi

echo "==> Running tests..."
go test -v ./...
