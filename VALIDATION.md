# Validation - initial release

This file captures evidence that the sandbox enforces the containment claims
in [`DESIGN.md`](DESIGN.md). It is updated on each release and should be
re-run by a deployer after any change to the Dockerfiles or compose stack.

## Environment

| Component         | Version                                |
| ----------------- | -------------------------------------- |
| Host OS           | macOS (Darwin 25.4.0)                  |
| Docker Engine     | Docker Desktop, Compose v2.31          |
| Bridge base image | `node:22-bookworm-slim`                |
| ET version        | `@evenrealities/even-terminal@0.7.9`   |
| Proxy             | `debian:bookworm-slim` + tinyproxy     |
| Publisher         | `alpine/socat:1.7.4.4`                 |
| Test runner       | `bats-core 1.13.0`                     |

## Result summary

```
01-auth.bats
 ✓ GET /api/info without token returns 401
 ✓ GET /api/info with wrong token returns 401
 ✓ GET /api/info with valid token returns 200
 ✓ bridge port is not reachable on a non-loopback host interface

02-isolation.bats
 ✓ bridge runs as non-root (uid 10001)
 ✓ bridge has no Linux capabilities
 ✓ bridge root filesystem is read-only
 ✓ bridge has NoNewPrivs set
 ✓ host SSH/cloud creds are NOT mounted in the bridge
 ✓ host's real ~/.claude is NOT visible inside the bridge
 ✓ /work is writable by the agent UID
 ✓ bridge image does NOT contain curl, wget, git, or ssh

03-egress.bats
 ✓ bridge has NO direct route to the public internet
 ✓ allowlisted host reaches origin VIA proxy (api.anthropic.com)
 ✓ non-allowlisted host is REFUSED at the proxy (example.com)
 ✓ non-allowlisted host is BLOCKED on a fictional domain

04-secrets.bats
 ✓ anthropic_api_key secret is mounted at /run/secrets and not world-readable
 ✓ bridge_token secret file matches the host file we expect
 ✓ image layers do NOT contain the bridge_token (sanity)

05-upstream-flags.bats
 ✓ entrypoint rejects --expose pinggy
 ✓ entrypoint refuses to start without HTTPS_PROXY
 ✓ entrypoint refuses to start with empty bridge_token secret

22 tests, 0 failures
```

## What each test class proves

- **01-auth** - the upstream auth middleware is wired and reachable; the
  published port is loopback-only (DESIGN §4 T7, T8).
- **02-isolation** - DESIGN §4 T1, T2, T3 containment claims (non-root,
  capability-dropped, read-only rootfs, NoNewPrivs, no host secrets mounted,
  minimal runtime tool surface).
- **03-egress** - DESIGN §5 egress-allowlist guarantees: direct internet
  egress is blocked at L3; allowlisted hosts pass; non-allowlisted hosts are
  refused at the CONNECT phase.
- **04-secrets** - Docker secrets are mounted only at `/run/secrets/` with
  correct perms; bridge_token does not appear in image layers (would fail T6
  if it did).
- **05-upstream-flags** - entrypoint guardrails: refuses `--expose` (DESIGN
  §4 T5), refuses to start without HTTPS_PROXY (defense against accidental
  direct-egress misconfiguration), refuses empty token secret.

## Findings during validation

The following issues were discovered and fixed during the validation loop;
listed here as a regression guide for future maintainers.

| # | Symptom                                                                                          | Root cause                                                                                                    | Fix                                                                                                    |
|---|--------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| 1 | `secret-init.sh` silently captured the operator's shell `OPENAI_API_KEY`                          | Script eagerly read any env var that happened to be set                                                       | OpenAI is now opt-in via `--with-openai`                                                               |
| 2 | mitmproxy's `--allow-hosts` was bypassed when combined with `--ignore-hosts '.*'`                | mitmproxy applies host filters AFTER the TLS-intercept decision; `--ignore-hosts` short-circuits the check     | Replaced mitmproxy with tinyproxy, which has a CONNECT-phase `FilterDefaultDeny` directive             |
| 3 | The bridge's host port did not publish when the container sat on an `internal: true` network     | Docker Desktop's vpnkit port forwarder cannot reach containers behind an internal-only network                | Added a single-purpose `publisher` sidecar (alpine/socat) on both an internal and a non-internal net   |
| 4 | The `non-allowlisted host is BLOCKED` test passed even when the proxy returned a 403             | Node's `http.request({method:"CONNECT"})` fires the `connect` event for ANY proxy response, not just 2xx ones | Test now reads `res.statusCode` from the `connect` callback and treats only 2xx as "allowed"           |
| 5 | The egress-proxy refused to start with `tmpfs ... mode=0700` on `/home/mitmproxy/.mitmproxy`     | Docker tmpfs `mode=` only sets the directory bits; ownership defaults to root, so uid 10001 cannot write     | When we switched to tinyproxy, this went away - tinyproxy's writable dirs are owned via chown in build |

## How to re-run

```sh
cp .env.example .env
$EDITOR .env                       # set PROJECT_DIR
ANTHROPIC_API_KEY=dummy scripts/secret-init.sh
docker compose build
scripts/up.sh
bats tests/
```

CI runs the same suite on every PR; see
[`.github/workflows/test.yaml`](.github/workflows/test.yaml).
