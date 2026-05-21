#!/bin/sh
# Sandbox entrypoint.
#
# Reads Docker secrets from /run/secrets/* and exports them as the env vars
# that @evenrealities/even-terminal expects, then execs ET. Keeping the read
# here (rather than in compose) means the secret content never appears in
# `docker inspect` output, only the file path.
#
# This script intentionally:
#   - is POSIX sh (no bash-isms)
#   - has set -eu, but NOT set -x (would echo secrets)
#   - does not write secrets to disk
#   - refuses to start if a required secret is missing

set -eu

err() { printf 'sandbox-entrypoint: %s\n' "$*" >&2; exit 1; }

read_secret() {
    # $1 = path, $2 = env var name. Exports var if file exists and is non-empty.
    _path="$1"
    _name="$2"
    if [ ! -r "$_path" ]; then
        err "missing required secret: $_path (expected as docker secret '$_name')"
    fi
    # Reject zero-length secret files.
    if [ ! -s "$_path" ]; then
        err "secret file $_path is empty"
    fi
    # `IFS= read -r` preserves a single line without trailing newline.
    IFS= read -r _value < "$_path"
    if [ -z "$_value" ]; then
        err "secret file $_path has no content on its first line"
    fi
    eval "export $_name=\$_value"
    unset _value
}

read_secret /run/secrets/anthropic_api_key ANTHROPIC_API_KEY
read_secret /run/secrets/bridge_token BRIDGE_TOKEN

# Optional secrets.
if [ -r /run/secrets/openai_api_key ] && [ -s /run/secrets/openai_api_key ]; then
    IFS= read -r OPENAI_API_KEY < /run/secrets/openai_api_key
    export OPENAI_API_KEY
fi

# Refuse to start if HTTPS_PROXY isn't set - this image is designed to egress
# only through the sidecar proxy. If the operator deliberately wants direct
# egress they must set EVEN_SANDBOX_ALLOW_DIRECT_EGRESS=1.
if [ -z "${HTTPS_PROXY:-}" ] && [ "${EVEN_SANDBOX_ALLOW_DIRECT_EGRESS:-0}" != "1" ]; then
    err "HTTPS_PROXY is not set; refusing to start (override with EVEN_SANDBOX_ALLOW_DIRECT_EGRESS=1)"
fi

# Refuse --expose flags. Operators are not allowed to publish the bridge via
# pinggy/bore from inside the sandbox (see DESIGN.md §4 T5).
for arg in "$@"; do
    case "$arg" in
        --expose|--expose=*)
            err "--expose is forbidden in this sandbox; use Tailscale on the host"
            ;;
    esac
done

# Pass --token from secret. ET respects $BRIDGE_TOKEN env directly, so no
# argv munging needed; we just exec it.
exec /usr/local/bin/even-terminal "$@"
