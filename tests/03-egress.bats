#!/usr/bin/env bats
# Egress containment: the bridge must reach allowlisted hosts via the proxy
# and must NOT reach anything else, including direct (non-proxy) traffic.

load helpers

teardown() { dump_on_failure; }

# These tests run from inside the bridge container. The bridge image
# intentionally lacks curl/wget, so we use node's http for HTTP and a tiny
# socket script for TCP reachability.

@test "bridge has NO direct route to the public internet" {
  # Direct TCP to api.anthropic.com:443 (bypassing proxy) must fail because
  # the 'app' compose network is internal:true.
  run bridge_exec node -e '
    const net = require("net");
    const s = net.createConnection({host:"api.anthropic.com",port:443,timeout:3000});
    s.on("connect", () => { console.log("CONNECTED"); s.destroy(); process.exit(0); });
    s.on("error",   () => { console.log("BLOCKED");   process.exit(0); });
    s.on("timeout", () => { console.log("TIMEOUT");   s.destroy(); process.exit(0); });
  '
  [ "$status" -eq 0 ]
  [ "$output" != "CONNECTED" ]
}

@test "allowlisted host reaches origin VIA proxy (api.anthropic.com)" {
  # Allowed CONNECTs return 200 from the proxy after establishing the TCP
  # tunnel to the origin.
  run bridge_exec node -e '
    const http = require("http");
    const url = new URL(process.env.HTTPS_PROXY);
    const req = http.request({
      host: url.hostname, port: url.port, method: "CONNECT",
      path: "api.anthropic.com:443", timeout: 8000,
    });
    req.on("connect", (res, sock) => { sock.destroy(); console.log("STATUS:" + res.statusCode); process.exit(0); });
    req.on("error",   (e) => { console.log("ERR:"+e.code); process.exit(0); });
    req.on("timeout", () => { console.log("TIMEOUT"); req.destroy(); process.exit(0); });
    req.end();
  '
  [ "$status" -eq 0 ]
  [ "$output" = "STATUS:200" ]
}

# Node fires `connect` for any CONNECT response, including 403s. We check the
# CONNECT status code explicitly: 2xx = allowed, anything else = refused.

@test "non-allowlisted host is REFUSED at the proxy (example.com)" {
  run bridge_exec node -e '
    const http = require("http");
    const url = new URL(process.env.HTTPS_PROXY);
    const req = http.request({
      host: url.hostname, port: url.port, method: "CONNECT",
      path: "example.com:443", timeout: 8000,
    });
    req.on("connect",  (res, sock) => { sock.destroy(); console.log("STATUS:" + res.statusCode); process.exit(0); });
    req.on("response", (res) => { console.log("STATUS:" + res.statusCode); process.exit(0); });
    req.on("error",    () => { console.log("STATUS:ERR"); process.exit(0); });
    req.on("timeout",  () => { console.log("STATUS:TIMEOUT"); req.destroy(); process.exit(0); });
    req.end();
  '
  [ "$status" -eq 0 ]
  # tinyproxy returns 403 Forbidden for filtered domains; anything that
  # is NOT 200 means the CONNECT was refused.
  echo "got: $output" >&2
  case "$output" in
    STATUS:200) false ;;
    STATUS:2*)  false ;;
    *)          : ;;
  esac
}

@test "non-allowlisted host is BLOCKED on a fictional domain" {
  run bridge_exec node -e '
    const http = require("http");
    const url = new URL(process.env.HTTPS_PROXY);
    const req = http.request({
      host: url.hostname, port: url.port, method: "CONNECT",
      path: "totally-not-allowlisted-evilcorp.invalid:443", timeout: 5000,
    });
    req.on("connect",  (res, sock) => { sock.destroy(); console.log("STATUS:" + res.statusCode); process.exit(0); });
    req.on("response", (res) => { console.log("STATUS:" + res.statusCode); process.exit(0); });
    req.on("error",    () => { console.log("STATUS:ERR"); process.exit(0); });
    req.on("timeout",  () => { console.log("STATUS:TIMEOUT"); req.destroy(); process.exit(0); });
    req.end();
  '
  echo "got: $output" >&2
  case "$output" in
    STATUS:200) false ;;
    STATUS:2*)  false ;;
    *)          : ;;
  esac
}
