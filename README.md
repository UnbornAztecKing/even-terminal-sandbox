# even-terminal-sandbox

A hardened Docker stack for running [`@evenrealities/even-terminal`][et] inside
a corporate environment. The upstream package opens an HTTP+SSE bridge on a
developer's host that lets an Even Realities phone/glasses client drive a
Claude Code or Codex agent over the host's filesystem. Out of the box it grants
broad tool access and ships with several auto-approval shortcuts that
materially weaken the per-call user-consent flow.

This project does not modify ET. Instead it wraps ET so that a compromised
token or a prompt-injection payload cannot escape a tightly scoped container.

[et]: https://www.npmjs.com/package/@evenrealities/even-terminal

See [`DESIGN.md`](DESIGN.md) for the threat model and architecture, and
[`docs/UPSTREAM-FINDINGS.md`](docs/UPSTREAM-FINDINGS.md) for the upstream
behaviors this sandbox contains.

---

## What it gives you

- **Non-root, capability-dropped, read-only-rootfs container** running ET as
  UID 10001. No SSH/cloud creds in the container; no `curl`/`wget`/`git`/`ssh`
  in the runtime image.
- **Egress-allowlist sidecar** (tinyproxy with `FilterDefaultDeny`) that
  refuses CONNECT to anything outside a vetted set of hosts. The bridge
  container has no direct L3 route to the public internet - it sits on an
  `internal: true` Docker network whose only sibling is the proxy.
- **Inbound forwarder sidecar** (alpine/socat) on a non-internal network so
  Docker can publish the bridge port to the host. The forwarder has no
  shell, no agent code, and no filesystem access.
- **Docker secrets** for the Anthropic API key and bridge token, mounted from
  `secrets/*` (gitignored) into `/run/secrets/*`. Secrets never appear in
  image layers, `docker inspect`, or compose YAML.
- **Loopback-only port publish**; remote access is granted via Tailscale on
  the host. Pinggy/bore tunnels are forbidden by the entrypoint.
- **Multi-arch images** (linux/amd64, linux/arm64) signed with cosign keyless
  OIDC and attested with SLSA L3 build provenance. CycloneDX SBOMs are
  attached to each release.

## What it does NOT defend against

- LLM-side exfil. The model provider sees every prompt and every Read result.
  Treat `/work` as if it were posted to the provider.
- A malicious operator. Anyone with `docker exec` on the host can override
  every protection here.

## Quickstart

Requirements: Docker 24+, `docker compose` v2, `openssl` (or `/dev/urandom`).

```sh
git clone https://github.com/UnbornAztecKing/even-terminal-sandbox
cd even-terminal-sandbox

cp .env.example .env
$EDITOR .env                       # set PROJECT_DIR

ANTHROPIC_API_KEY=sk-ant-... scripts/secret-init.sh
scripts/up.sh                      # build + start

scripts/qr.sh                      # prints a Tailscale-host URL + QR
```

Scan the QR from the Even Realities phone app.

To stop the stack: `scripts/down.sh`. To wipe agent session state:
`scripts/down.sh -v`.

### Reaching the bridge from the phone

The bridge is published only on `127.0.0.1:3456`. The phone reaches it via
Tailscale on the host:

```sh
tailscale serve --bg --http=3456 http://localhost:3456
```

`scripts/qr.sh` reads `tailscale status --json` to build the QR URL and
warns if the serve rule isn't in place.

## Verification (release builds)

Verify the bridge image signature:

```sh
cosign verify ghcr.io/unbornaztecking/even-terminal-sandbox:<tag> \
  --certificate-identity-regexp '^https://github\.com/UnbornAztecKing/even-terminal-sandbox/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

Verify SLSA build provenance:

```sh
gh attestation verify oci://ghcr.io/unbornaztecking/even-terminal-sandbox:<tag> \
  --repo UnbornAztecKing/even-terminal-sandbox
```

Inspect the CycloneDX SBOM:

```sh
cosign download attestation \
  --predicate-type https://cyclonedx.org/bom \
  ghcr.io/unbornaztecking/even-terminal-sandbox:<tag>
```

## Platform support

| Platform                         | Status       | Notes                                                                |
| -------------------------------- | ------------ | -------------------------------------------------------------------- |
| Linux server, amd64              | first-class  | Primary corporate target.                                             |
| Linux server, arm64              | first-class  | Graviton / Ampere fleets.                                             |
| Linux developer workstation      | first-class  | Same image as servers.                                                |
| macOS developer workstation      | supported    | Docker Desktop's Linux VM is an extra isolation layer.                |

## Testing

```sh
brew install bats-core   # or apt install bats / npm install -g bats
scripts/smoke.sh         # runs the bats suite against a live stack
```

The bats suite (`tests/`) checks:

- Auth: 401 on missing/wrong token; 200 on valid; port is loopback-only.
- Isolation: container UID, no caps, read-only rootfs, NoNewPrivs, host
  `~/.ssh`/`~/.aws`/`~/.claude` not visible, `/work` writable, runtime image
  free of `curl`/`wget`/`git`/`ssh`.
- Egress: no direct route from the bridge; allowlisted hosts pass; everything
  else is refused at the proxy.
- Secrets: mounted with correct perms; same hash inside and outside; not
  baked into image layers.
- Entrypoint guardrails: refuses `--expose`, refuses to start without
  `HTTPS_PROXY`, refuses empty token secret.

## Layout

```
.
├── Dockerfile                  # bridge image (multi-stage, multi-arch)
├── entrypoint.sh               # bridge entrypoint: reads secrets, refuses --expose
├── compose.yaml                # bridge + proxy stack
├── .env.example                # operator-facing config template
├── secrets/                    # gitignored; populated by secret-init.sh
├── proxy/
│   ├── Dockerfile              # tinyproxy allowlist sidecar
│   ├── allowlist.txt           # one regex per allowed host
│   └── entrypoint.sh
├── scripts/
│   ├── secret-init.sh          # generate bridge_token, write API key
│   ├── up.sh / down.sh         # lifecycle
│   ├── qr.sh                   # print Tailscale-host QR
│   └── smoke.sh                # run bats against live stack
├── tests/                      # bats integration suite
├── .github/workflows/          # lint / test / build+sign+sbom
├── DESIGN.md                   # threat model and architecture
└── docs/UPSTREAM-FINDINGS.md   # upstream behaviors this sandbox mitigates
```

## License

Apache-2.0. See [`LICENSE`](LICENSE).
