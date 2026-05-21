#!/bin/sh
# Bring up the sandbox. Validates env + secrets, then `docker compose up -d`.

set -eu

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1007
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

err() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

[ -f ./.env ] || err ".env not found. Copy .env.example to .env and edit PROJECT_DIR."

# shellcheck disable=SC1091
. ./.env

[ -n "${PROJECT_DIR:-}" ] || err "PROJECT_DIR is not set in .env"
[ -d "$PROJECT_DIR" ]      || err "PROJECT_DIR ($PROJECT_DIR) is not a directory"

for f in bridge_token anthropic_api_key; do
    target="./secrets/$f"
    [ -s "$target" ] || err "missing secret $target. Run scripts/secret-init.sh"
    perm=$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || echo "?")
    if [ "$perm" != "600" ]; then
        echo "warn: $target has mode $perm; chmod 600" >&2
        chmod 600 "$target"
    fi
done

exec docker compose up -d --build "$@"
