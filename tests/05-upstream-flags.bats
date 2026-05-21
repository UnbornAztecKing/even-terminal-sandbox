#!/usr/bin/env bats
# Sandbox-specific guardrails: the entrypoint must refuse to start with
# --expose, and must require HTTPS_PROXY unless explicitly overridden.

load helpers

teardown() { dump_on_failure; }

@test "entrypoint rejects --expose pinggy" {
  run docker run --rm --entrypoint /usr/local/bin/sandbox-entrypoint \
    -v "${BATS_TEST_DIRNAME}/../secrets/bridge_token:/run/secrets/bridge_token:ro" \
    -v "${BATS_TEST_DIRNAME}/../secrets/anthropic_api_key:/run/secrets/anthropic_api_key:ro" \
    -e HTTPS_PROXY=http://does-not-matter:3128 \
    "$(docker inspect --format '{{.Image}}' "$BRIDGE_CONTAINER")" \
    --expose pinggy
  [ "$status" -ne 0 ]
  echo "$output" | grep -q -- "--expose is forbidden"
}

@test "entrypoint refuses to start without HTTPS_PROXY" {
  run docker run --rm --entrypoint /usr/local/bin/sandbox-entrypoint \
    -v "${BATS_TEST_DIRNAME}/../secrets/bridge_token:/run/secrets/bridge_token:ro" \
    -v "${BATS_TEST_DIRNAME}/../secrets/anthropic_api_key:/run/secrets/anthropic_api_key:ro" \
    "$(docker inspect --format '{{.Image}}' "$BRIDGE_CONTAINER")"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "HTTPS_PROXY is not set"
}

@test "entrypoint refuses to start with empty bridge_token secret" {
  empty=$(mktemp)
  trap 'rm -f "$empty"' EXIT
  run docker run --rm --entrypoint /usr/local/bin/sandbox-entrypoint \
    -v "$empty:/run/secrets/bridge_token:ro" \
    -v "${BATS_TEST_DIRNAME}/../secrets/anthropic_api_key:/run/secrets/anthropic_api_key:ro" \
    -e HTTPS_PROXY=http://does-not-matter:3128 \
    "$(docker inspect --format '{{.Image}}' "$BRIDGE_CONTAINER")"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "empty"
}
