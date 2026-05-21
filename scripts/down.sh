#!/bin/sh
# Tear down the stack. Pass --volumes to wipe agent session state.

set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

exec docker compose down "$@"
