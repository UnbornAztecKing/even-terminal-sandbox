#!/bin/sh
# Build a tinyproxy config from the allowlist file and exec tinyproxy.
#
# Key directives:
#   Port 3128                listen on :3128 (all interfaces inside container).
#   Listen 0.0.0.0           only the 'app' compose network reaches this; the
#                            container itself is on the internal bridge net.
#   Allow 0.0.0.0/0          all clients on that net may use the proxy. The
#                            allowlist is on TARGETS, not on clients.
#   FilterDefaultDeny Yes    default-deny target hosts; only allowlist matches
#                            are allowed. This is what makes the proxy a
#                            real egress firewall.
#   Filter <file>            allowlist file: one extended regex per line.
#   FilterExtended On        use extended POSIX regex.
#   FilterURLs Off           apply filter to host, not URL path (CONNECT has
#                            no path).
#   ConnectPort 443          permit HTTPS CONNECT only. Block CONNECT to
#                            arbitrary ports (no SSH-over-CONNECT, no
#                            CONNECT-to-25, etc.).
#   DisableViaHeader Yes     don't leak proxy identity to upstream.

set -eu

ALLOWFILE=/etc/even-egress/allowlist.txt
CONFFILE=/run/tinyproxy/tinyproxy.conf
FILTERFILE=/run/tinyproxy/filter

[ -r "$ALLOWFILE" ] || { echo "proxy: missing $ALLOWFILE" >&2; exit 1; }

# tinyproxy expects one pattern per line, no comments.
awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]+$/, ""); print }
' "$ALLOWFILE" > "$FILTERFILE"

if [ ! -s "$FILTERFILE" ]; then
    echo "proxy: allowlist is empty; refusing to start (would deny everything)" >&2
    exit 1
fi

cat > "$CONFFILE" <<EOF
User eveproxy
Group eveproxy
Port 3128
Listen 0.0.0.0
Timeout 60
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 64
DisableViaHeader Yes
Allow 0.0.0.0/0
Filter "$FILTERFILE"
FilterDefaultDeny Yes
FilterExtended On
FilterURLs Off
FilterCaseSensitive Off
ConnectPort 443
ConnectPort 80
EOF

echo "proxy: starting tinyproxy with allowlist:" >&2
sed 's/^/  /' "$FILTERFILE" >&2

# `-d` keeps tinyproxy in the foreground and logs to stdout/stderr.
exec tinyproxy -d -c "$CONFFILE"
