#!/bin/sh
# client.sh fetches the laptop's page two ways and checks what comes back.
set -eu

want="hello from localhost:3000"
fetch() {
	curl -fsS --retry 60 --retry-delay 1 --retry-all-errors --cacert /tmp/root.pem "$@"
}

# Pebble makes a new root at each start. Trust it.
curl -fsS --retry 30 --retry-delay 1 --retry-all-errors \
	--cacert /etc/pebble.minica.pem https://pebble:15000/roots/0 >/tmp/root.pem

got=$(fetch https://api.example.test/)
echo "through the relay: $got"
[ "$got" = "$want" ]

dumbpipe connect-tcp --addr 127.0.0.1:8443 "$TICKET" 2>/dev/null &
got=$(fetch --resolve api.example.test:8443:127.0.0.1 https://api.example.test:8443/)
echo "straight over iroh: $got"
[ "$got" = "$want" ]
