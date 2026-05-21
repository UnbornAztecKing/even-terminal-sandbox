#!/usr/bin/env bats
# Filesystem and process isolation: the bridge container must NOT see host
# secrets, must run unprivileged, must have a read-only root filesystem, and
# must drop all Linux capabilities.

load helpers

teardown() { dump_on_failure; }

@test "bridge runs as non-root (uid 10001)" {
  run bridge_exec id -u
  [ "$status" -eq 0 ]
  [ "$output" = "10001" ]
}

@test "bridge has no Linux capabilities" {
  # CapEff is a hex bitmask of effective caps. Zero means none.
  run bridge_exec sh -c "grep '^CapEff:' /proc/1/status | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  # Strip leading zeros; 16-char field of zeros == no caps.
  printable=$(printf '%s' "$output" | tr -d '0')
  [ -z "$printable" ]
}

@test "bridge root filesystem is read-only" {
  run bridge_exec sh -c 'touch /should-fail 2>&1'
  [ "$status" -ne 0 ]
}

@test "bridge has NoNewPrivs set" {
  run bridge_exec sh -c "grep '^NoNewPrivs:' /proc/1/status | awk '{print \$2}'"
  [ "$output" = "1" ]
}

@test "host SSH/cloud creds are NOT mounted in the bridge" {
  # ~/.ssh, ~/.aws, ~/.config/gcloud should not exist inside the container.
  run bridge_exec sh -c 'test ! -e /home/even/.ssh && test ! -e /home/even/.aws && test ! -e /root/.ssh && echo ok'
  [ "$output" = "ok" ]
}

@test "host's real ~/.claude is NOT visible inside the bridge" {
  # The bridge sees its own (empty) named-volume .claude; it must not contain
  # any files from the host operator's pre-existing Claude Code history.
  # Specifically, the host's history would include "projects/" subdirs.
  run bridge_exec sh -c 'ls /home/even/.claude/projects 2>/dev/null | wc -l'
  [ "$status" -eq 0 ]
  # Zero entries means we mounted a clean volume, not the host dir.
  [ "$output" = "0" ]
}

@test "/work is writable by the agent UID" {
  run bridge_exec sh -c 'echo hello > /work/.sandbox-test && cat /work/.sandbox-test && rm /work/.sandbox-test'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "bridge image does NOT contain curl, wget, git, or ssh" {
  for tool in curl wget git ssh scp; do
    run bridge_exec sh -c "command -v $tool >/dev/null 2>&1 && echo present || echo absent"
    [ "$output" = "absent" ] || {
      echo "tool $tool is present in the runtime image" >&2
      false
    }
  done
}
