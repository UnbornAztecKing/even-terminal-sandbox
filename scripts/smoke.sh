#!/bin/sh
# Run the bats-based test suite against a running stack. Brings the stack up
# if it isn't, leaves it running on success, tears it down on --teardown.

set -eu
# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1007
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

TEARDOWN=0
for arg in "$@"; do
    case "$arg" in
        --teardown) TEARDOWN=1 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--teardown]"
            exit 0
            ;;
    esac
done

if ! command -v bats >/dev/null 2>&1; then
    cat <<EOF >&2
error: 'bats' not found.
Install with one of:
  brew install bats-core
  npm install -g bats
  apt install bats
EOF
    exit 1
fi

# Bring the stack up if not running.
if ! docker compose ps --status running --quiet bridge | grep -q .; then
    echo "smoke: bringing stack up..."
    ./scripts/up.sh
    # Wait for healthcheck.
    for _ in $(seq 1 30); do
        state=$(docker inspect -f '{{.State.Health.Status}}' even-bridge 2>/dev/null || echo "missing")
        if [ "$state" = "healthy" ]; then break; fi
        sleep 2
    done
    if [ "$state" != "healthy" ]; then
        echo "smoke: bridge did not become healthy (state=$state)" >&2
        docker compose logs --tail=80 bridge >&2 || true
        exit 1
    fi
fi

set +e
bats tests/
status=$?
set -e

if [ "$TEARDOWN" -eq 1 ]; then
    ./scripts/down.sh
fi

exit "$status"
