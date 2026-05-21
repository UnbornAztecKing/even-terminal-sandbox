# Security policy

## Scope

This policy covers the code and packaging in this repository:

- The `Dockerfile`s and entrypoint scripts that build the bridge and proxy
  images.
- The `compose.yaml` stack and `scripts/`.
- The GitHub Actions workflows that build, sign, and attest the published
  images.

It does **NOT** cover:

- `@evenrealities/even-terminal` itself. Vulnerabilities in the upstream
  package should be reported to Even Realities. The behaviors this sandbox
  contains are documented in [`docs/UPSTREAM-FINDINGS.md`](docs/UPSTREAM-FINDINGS.md).
- The Claude Agent SDK, mitmproxy, Node.js, Debian, or any other upstream
  dependency. Report to those projects directly.
- LLM-side exfiltration. By design, anything the agent can `Read` may be
  shipped to the model provider as part of normal operation.

## Reporting a vulnerability

Please report security issues privately via GitHub's "Report a vulnerability"
feature on this repository, or by email to the repository owner.

Include:

- The image tag and digest you tested against (`docker inspect --format
  '{{index .RepoDigests 0}}' even-bridge`).
- The version of `@evenrealities/even-terminal` baked into that image.
- A minimal reproduction.
- Your assessment of severity and impact under the sandbox's threat model
  (see [`DESIGN.md`](DESIGN.md) §4).

Please do not open public issues, discussions, or PRs that disclose
unpatched vulnerabilities.

## Disclosure timeline

We aim to:

- Acknowledge reports within 3 business days.
- Provide an initial assessment within 7 business days.
- Publish a fix and CVE (where applicable) within 90 days of receipt, or
  earlier if exploitation is observed in the wild.

## Supported versions

Only the latest tagged release is supported. We do not backport fixes to
older tags.

## Verification

Every published image is:

- Signed with cosign keyless OIDC from this repository's GitHub Actions.
- Accompanied by a CycloneDX SBOM attached as a cosign attestation.
- Accompanied by SLSA L3 build provenance.

See the verification commands in [`README.md`](README.md#verification-release-builds).
