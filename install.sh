#!/bin/sh
# install.sh installs dumbpipe. Given a ticket, it also runs the relay: a
# systemd service that forwards TCP port 443 to that ticket. Run it as root.
#
#   sh install.sh           # only install dumbpipe
#   sh install.sh TICKET    # install dumbpipe and run the relay
set -eu

ticket=${1:-}
version=v0.39.0
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
[ "$arch" = arm64 ] && arch=aarch64
curl -fsSL "https://github.com/n0-computer/dumbpipe/releases/download/$version/dumbpipe-$version-$os-$arch.tar.gz" |
	tar -xz -C /usr/local/bin ./dumbpipe
[ -n "$ticket" ] || exit 0

cat >/etc/systemd/system/dumbtunnel.service <<EOF
[Unit]
Description=dumbtunnel relay
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/dumbpipe connect-tcp --addr 0.0.0.0:443 $ticket
Environment=RUST_LOG=warn
DynamicUser=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Oracle's Ubuntu images reject inbound traffic in iptables.
if command -v netfilter-persistent >/dev/null; then
	iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null ||
		iptables -I INPUT -p tcp --dport 443 -j ACCEPT
	netfilter-persistent save
fi
systemctl daemon-reload
systemctl enable dumbtunnel
systemctl restart dumbtunnel
