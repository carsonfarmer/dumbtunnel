#!/bin/sh
# run.sh runs the end-to-end test in Docker. It needs the network, because
# iroh finds the laptop through the n0 relays and DNS.
set -eu
cd "$(dirname "$0")"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dumbtunnel-test}"
trap 'docker compose down -v -t 1' EXIT

docker compose build
TICKET=$(docker compose run --rm -T --no-deps laptop dumbtunnel ticket)
export TICKET
echo "ticket: $TICKET"
docker compose up -t 1 --exit-code-from client
