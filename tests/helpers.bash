# shellcheck shell=bash
# Shared helpers for the bats suite. Bats sources this via `load helpers`.

BRIDGE_CONTAINER=${BRIDGE_CONTAINER:-even-bridge}
PROXY_CONTAINER=${PROXY_CONTAINER:-even-egress-proxy}
BRIDGE_PORT=${BRIDGE_PORT:-3456}
# shellcheck disable=SC2034  # used by .bats files that source this helper
BRIDGE_URL="http://127.0.0.1:${BRIDGE_PORT}"

token() {
  head -n1 "${BATS_TEST_DIRNAME}/../secrets/bridge_token"
}

# Exec a command inside the bridge container. Fails the test if the container
# isn't running.
bridge_exec() {
  docker exec "$BRIDGE_CONTAINER" "$@"
}

proxy_exec() {
  docker exec "$PROXY_CONTAINER" "$@"
}

# Pretty-print docker logs if a test fails.
dump_on_failure() {
  if [ "${BATS_TEST_COMPLETED:-0}" != "1" ]; then
    echo "--- bridge logs (last 40) ---" >&3
    docker logs --tail=40 "$BRIDGE_CONTAINER" 2>&1 | sed 's/^/  /' >&3 || true
    echo "--- proxy logs (last 40) ---" >&3
    docker logs --tail=40 "$PROXY_CONTAINER" 2>&1 | sed 's/^/  /' >&3 || true
  fi
}
