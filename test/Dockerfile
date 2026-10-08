# Images for the end-to-end test. Pebble is Let's Encrypt's test CA. The
# last stage plays the laptop, the relay and the browser.
FROM caddy:2.11.7 AS caddy

FROM ghcr.io/letsencrypt/pebble:2.10.1 AS pebble
COPY test/pebble.json /test/config/pebble-config.json

FROM alpine:3.24
RUN apk add --no-cache curl
COPY install.sh /tmp/
RUN sh /tmp/install.sh
COPY --from=caddy /usr/bin/caddy /usr/local/bin/
COPY --from=pebble /test/certs/pebble.minica.pem /etc/
COPY dumbtunnel /usr/local/bin/
# The laptop serves Caddyfile.example, with the test's domain.
COPY Caddyfile.example /tmp/
RUN adduser -D laptop && mkdir -p /home/laptop/.config/dumbtunnel && \
	sed 's/you\.duckdns\.org/example.test/g' /tmp/Caddyfile.example >/home/laptop/Caddyfile && \
	chown -R laptop /home/laptop
