#!/bin/sh
# Initialize the Docker secret files this stack requires.
#
# Generates a strong bridge token (32 bytes of /dev/urandom hex).
# Prompts (or accepts from env) the Anthropic API key.
# Writes files into ./secrets/ with mode 0600.
#
# Safe to re-run; refuses to overwrite existing files unless --force.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SECRETS_DIR="$REPO_ROOT/secrets"

FORCE=0
WITH_OPENAI=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        --with-openai) WITH_OPENAI=1 ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--force] [--with-openai]

Creates:
  $SECRETS_DIR/bridge_token         (32-byte hex, generated)
  $SECRETS_DIR/anthropic_api_key    (from \$ANTHROPIC_API_KEY or prompt)
  $SECRETS_DIR/openai_api_key       (only if --with-openai is passed)

All files written with mode 0600. OpenAI is opt-in to avoid accidentally
picking up an unrelated \$OPENAI_API_KEY from the operator's shell.
EOF
            exit 0
            ;;
        *)
            echo "$(basename "$0"): unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$SECRETS_DIR"
chmod 0700 "$SECRETS_DIR"

write_secret() {
    # $1 = filename, $2 = content
    target="$SECRETS_DIR/$1"
    if [ -e "$target" ] && [ "$FORCE" -ne 1 ]; then
        echo "skip: $target already exists (use --force to overwrite)" >&2
        return 0
    fi
    # Write with mode 0600 atomically.
    umask 077
    printf '%s\n' "$2" > "$target.tmp"
    mv "$target.tmp" "$target"
    chmod 0600 "$target"
    echo "wrote $target"
}

# Bridge token: 32 random bytes hex (256-bit).
if command -v openssl >/dev/null 2>&1; then
    TOKEN=$(openssl rand -hex 32)
elif [ -r /dev/urandom ]; then
    TOKEN=$(od -An -N32 -tx1 < /dev/urandom | tr -d ' \n')
else
    echo "error: no source of randomness (openssl or /dev/urandom required)" >&2
    exit 1
fi
write_secret bridge_token "$TOKEN"
unset TOKEN

# Anthropic API key.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    write_secret anthropic_api_key "$ANTHROPIC_API_KEY"
else
    if [ -t 0 ]; then
        printf 'Anthropic API key (input hidden): ' >&2
        stty -echo 2>/dev/null || true
        IFS= read -r APIKEY
        stty echo 2>/dev/null || true
        printf '\n' >&2
        if [ -z "$APIKEY" ]; then
            echo "error: empty API key" >&2
            exit 1
        fi
        write_secret anthropic_api_key "$APIKEY"
        unset APIKEY
    else
        echo "error: ANTHROPIC_API_KEY not set and stdin is not a tty" >&2
        exit 1
    fi
fi

# OpenAI is opt-in via --with-openai. We deliberately do NOT inherit from a
# bare $OPENAI_API_KEY in the operator's shell environment, because that
# variable is commonly set for unrelated tooling and silently materializing it
# into a secret file is a foot-gun.
if [ "$WITH_OPENAI" -eq 1 ]; then
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        write_secret openai_api_key "$OPENAI_API_KEY"
    elif [ -t 0 ]; then
        printf 'OpenAI API key (input hidden): ' >&2
        stty -echo 2>/dev/null || true
        IFS= read -r OAIKEY
        stty echo 2>/dev/null || true
        printf '\n' >&2
        if [ -n "$OAIKEY" ]; then
            write_secret openai_api_key "$OAIKEY"
            unset OAIKEY
        fi
    fi
fi

echo "done. Secrets directory: $SECRETS_DIR"
echo "next: docker compose up -d  (then scripts/qr.sh)"
