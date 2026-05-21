#!/bin/sh
# Print a connection QR pointing at the Tailscale-resolved host, not the
# container's LAN IP. This keeps token-bearing URLs off any non-tailnet path.
#
# Resolution order for the host:
#   1. EVEN_QR_HOST env var (operator override)
#   2. `tailscale status --json` DNS name (preferred; what the phone hits)
#   3. `tailscale ip -4` first address
#   4. error out - refuse to print a LAN URL.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

err() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# shellcheck disable=SC1091
[ -f ./.env ] && . ./.env
PORT=${BRIDGE_PORT:-3456}

[ -s ./secrets/bridge_token ] || err "missing ./secrets/bridge_token; run scripts/secret-init.sh"
TOKEN=$(head -n1 ./secrets/bridge_token)

HOST=${EVEN_QR_HOST:-}
if [ -z "$HOST" ]; then
    if command -v tailscale >/dev/null 2>&1; then
        DNS=$(tailscale status --json 2>/dev/null \
            | sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)\..*/\1/p' \
            | head -n1)
        if [ -n "$DNS" ]; then
            HOST="$DNS"
        else
            HOST=$(tailscale ip -4 2>/dev/null | head -n1)
        fi
    fi
fi

[ -n "$HOST" ] || err "could not resolve a tailnet host. Set EVEN_QR_HOST or run \`tailscale up\`."

# Reminder: the bridge is published on 127.0.0.1 only. The operator MUST run
# `tailscale serve --bg --http=$PORT http://localhost:$PORT` so the tailnet
# host above actually points at the bridge.
if command -v tailscale >/dev/null 2>&1; then
    if ! tailscale serve status 2>/dev/null | grep -q "127.0.0.1:$PORT"; then
        cat <<EOF >&2
warn: 'tailscale serve' does not appear to be forwarding :$PORT.
warn: phone will not reach the bridge unless you run:
warn:   tailscale serve --bg --http=$PORT http://localhost:$PORT
EOF
    fi
fi

URL="http://$HOST:$PORT?token=$TOKEN&defaultProvider=claude"

printf '\n  Connection URL:\n  %s\n\n' "$URL"

if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 -m 1 "$URL"
elif command -v segno >/dev/null 2>&1; then
    segno --output=- --kind=ansi "$URL"
else
    cat <<EOF >&2
Tip: install 'qrencode' (brew install qrencode / apt install qrencode) to
render a scannable QR in this terminal. The URL above can be turned into a QR
by any QR generator; scan it from the Even Realities app.
EOF
fi
