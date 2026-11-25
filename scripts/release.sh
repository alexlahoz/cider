#!/bin/bash
# Everything from scratch: runtime → app → dmg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-runtime.sh"
"$ROOT/scripts/build-app.sh"
"$ROOT/scripts/make-dmg.sh"
