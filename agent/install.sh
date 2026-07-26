#!/usr/bin/env sh
set -eu
TOKEN=""; LISTEN=":9977"; DOWNLOAD_BASE="https://example.invalid/aster-agent/releases"
while [ "$#" -gt 0 ]; do case "$1" in --token) TOKEN="$2"; shift 2;; --listen) LISTEN="$2"; shift 2;; *) shift;; esac; done
[ -n "$TOKEN" ] || { echo "--token is required" >&2; exit 1; }
ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; *) echo "unsupported architecture: $ARCH" >&2; exit 1;; esac
curl -fsSL "$DOWNLOAD_BASE/aster-agent-linux-$ARCH" -o /usr/local/bin/aster-agent
chmod 755 /usr/local/bin/aster-agent
cat >/etc/systemd/system/aster-agent.service <<EOF
[Unit]
Description=Aster Agent
After=network-online.target
[Service]
ExecStart=/usr/local/bin/aster-agent --listen $LISTEN --token $TOKEN
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now aster-agent
