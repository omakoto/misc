#!/bin/bash
# Setup script to initialize go.work if it doesn't exist for tout.

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f go.work ]]; then
  echo "==> Creating go.work..."
  GOWORK=off go work init
  go work use .
fi
