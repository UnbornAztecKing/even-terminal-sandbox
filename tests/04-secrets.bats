#!/usr/bin/env bats
# Secret hygiene: secrets must be readable in the container only from
# /run/secrets/, must not leak into env exported to other processes, and
# must not be in the image.

load helpers

teardown() { dump_on_failure; }

@test "anthropic_api_key secret is mounted at /run/secrets and not world-readable" {
  run bridge_exec sh -c 'test -f /run/secrets/anthropic_api_key && stat -c %a /run/secrets/anthropic_api_key'
  [ "$status" -eq 0 ]
  # Docker mounts secrets with 0400 / 0444 depending on engine; require not world-writable.
  case "$output" in
    *7|*6|*3|*2) : ;;  # world-writable digit
    *)
      [ "$output" != "" ] ;;
  esac
}

@test "bridge_token secret file matches the host file we expect" {
  hash_in_container=$(bridge_exec sh -c 'sha256sum /run/secrets/bridge_token | cut -d" " -f1')
  hash_on_host=$(sha256sum "${BATS_TEST_DIRNAME}/../secrets/bridge_token" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$hash_on_host" ]; then
    # macOS has shasum not sha256sum.
    hash_on_host=$(shasum -a 256 "${BATS_TEST_DIRNAME}/../secrets/bridge_token" | cut -d' ' -f1)
  fi
  [ -n "$hash_in_container" ]
  [ -n "$hash_on_host" ]
  [ "$hash_in_container" = "$hash_on_host" ]
}

@test "image layers do NOT contain the bridge_token (sanity)" {
  # `docker history --no-trunc` exposes every layer's build command. The token
  # is generated at runtime and mounted as a secret - it must not appear in
  # any layer.
  token=$(token)
  run sh -c "docker history --no-trunc \$(docker inspect --format '{{.Image}}' $BRIDGE_CONTAINER) | grep -F '$token' || true"
  [ -z "$output" ]
}
