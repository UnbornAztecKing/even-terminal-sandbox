#!/usr/bin/env bats
# Auth gate: bridge MUST reject requests without a valid bearer token.

load helpers

teardown() { dump_on_failure; }

@test "GET /api/info without token returns 401" {
  run curl -s -o /dev/null -w '%{http_code}' "${BRIDGE_URL}/api/info"
  [ "$status" -eq 0 ]
  [ "$output" = "401" ]
}

@test "GET /api/info with wrong token returns 401" {
  run curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer not-the-real-token-just-some-string" \
    "${BRIDGE_URL}/api/info"
  [ "$status" -eq 0 ]
  [ "$output" = "401" ]
}

@test "GET /api/info with valid token returns 200" {
  run curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $(token)" \
    "${BRIDGE_URL}/api/info"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "bridge port is not reachable on a non-loopback host interface" {
  # If `host.docker.internal` resolves on the host, the loopback-only publish
  # is configured correctly: the bridge port is unreachable from any IP that
  # isn't 127.0.0.1.
  host_ip=$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | head -n1)
  if [ -z "$host_ip" ]; then
    skip "could not determine a non-loopback host IP"
  fi
  run curl --max-time 2 -s -o /dev/null -w '%{http_code}' "http://${host_ip}:${BRIDGE_PORT}/api/info"
  # Expect curl to fail (connection refused / timeout) → http_code "000".
  [ "$output" = "000" ]
}
