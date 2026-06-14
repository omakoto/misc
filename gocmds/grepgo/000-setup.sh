#!/bin/bash
# Setup script to initialize go.work if it doesn't exist.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f go.work ]]; then
  echo "==> Creating go.work..."
  # Use GOWORK=off to prevent go work init from referencing parent workspaces
  GOWORK=off go work init
  go work use .
fi
