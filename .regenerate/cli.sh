#!/bin/sh
# cli.sh checks the dumbtunnel command against SPEC.md. check.sh runs it as
# the laptop user in the test image, where dumbtunnel, dumbpipe and caddy are
# on PATH. It needs the network, because dumbpipe comes online through the
# n0 relays. It never contacts a real CA: DUMBTUNNEL_ACME_CA always points at
# a closed port or at an nc stand-in that only records what Caddy sends.
set -u

T=$(mktemp -d)
export HOME="$T/home"
work=$T/work
mkdir -p "$HOME" "$work"
cd "$work" || exit 1
unset DUMBTUNNEL_DIR DUMBTUNNEL_PORT XDG_CONFIG_HOME XDG_DATA_HOME
export DUMBTUNNEL_ACME_CA=https://127.0.0.1:1/directory
fails=$T/fails
: >"$fails"
n=0

# Actors run in the background, so failures go to a file.
fail() { echo "FAIL: $name: $*" | tee -a "$fails" >&2; }

# start NAME prints a heading and gives the run its own directory, c.
start() {
	name=$1
	n=$((n + 1))
	c=$T/run$n
	mkdir "$c"
	echo "== $name"
}

# run ACTOR ARGS... runs dumbtunnel ARGS in its own session, in the working
# directory, with ACTOR DIR checking on it. dumbtunnel runs in the
# foreground, because a background job here would ignore SIGINT. Its CA is a
# stand-in that records the first bytes Caddy sends to DIR/ca.
run() {
	actor=$1
	shift
	ls -A "$work" >"$c/before"
	caport=$((20000 + n))
	nc -l -p "$caport" >"$c/ca" 2>/dev/null &
	ca=$!
	"$actor" "$c" &
	a=$!
	# shellcheck disable=SC2016 # The inner shell expands these.
	DUMBTUNNEL_ACME_CA="https://127.0.0.1:$caport/directory" \
		setsid sh -c 'echo $$ >"$0"; exec dumbtunnel "$@"' "$c/pid" "$@" </dev/null >"$c/out" 2>"$c/err"
	echo $? >"$c/status"
	wait "$a"
	kill "$ca" 2>/dev/null
	if [ "$(wc -l <"$fails")" -gt "${seen:-0}" ]; then
		echo "-- stdout:" && cat "$c/out"
		echo "-- stderr:" && grep -v 'secret key' "$c/err" | tail -n 20
	fi
	seen=$(wc -l <"$fails")
}

status() { cat "$1/status" 2>/dev/null; }
sid() { cat "$1/pid"; }

# alive SID prints the live processes in session SID.
alive() {
	cat /proc/[0-9]*/stat 2>/dev/null |
		awk -v sid="$1" '{ pid = $1; sub(/.*\) /, ""); if ($4 == sid && $1 != "Z") print pid }'
}

# listening tcp|udp prints the ports with a listening socket, leaving out
# the ones that were open before the first run, such as Docker's DNS.
listening() {
	if [ "$1" = tcp ]; then netstat -ltn; else netstat -lnu; fi |
		awk 'NR > 2 { sub(/.*:/, "", $4); print $4 }' | sort -un | grep -vxF "$(printf '%s\n' "$base" 0)"
}

# within SECONDS COMMAND... retries COMMAND once a second.
within() {
	s=$1
	shift
	i=0
	until "$@"; do
		i=$((i + 1))
		[ $i -lt "$s" ] || return 1
		sleep 1
	done
}

exited() { [ -s "$1/status" ]; }
ticketed() { grep -q '^ticket: ' "$1/out" 2>/dev/null || exited "$1"; }
quiet() { [ -z "$(alive "$1")" ]; }
free() { ! listening tcp | grep -qx "$1"; }
accepts() { nc -z -w 1 127.0.0.1 "$1"; }
contacted() { [ -s "$1" ]; }

# ready DIR waits for the ticket line.
ready() {
	within 60 ticketed "$1" || { fail "no ticket line within 60 seconds"; return 1; }
	! exited "$1" || { fail "exited with status $(status "$1") instead of serving"; return 1; }
}

# stop DIR SIGNAL [group] sends SIGNAL to dumbtunnel, or to its process
# group, and waits for it to exit.
stop() {
	p=$(sid "$1")
	[ "${3:-}" = group ] && p=-$p
	kill -s "$2" "$p" 2>/dev/null
	within 30 exited "$1" && return
	fail "still running 30 seconds after SIG$2"
	kill -s KILL "-$(sid "$1")" 2>/dev/null
}

# finish DIR waits for dumbtunnel to exit on its own.
finish() {
	within 90 exited "$1" && return
	fail "still running after 90 seconds"
	kill -s KILL "-$(sid "$1")" 2>/dev/null
}

# stopped DIR checks the exit status after a signal or a failure.
stopped() { [ "$(status "$1")" != 0 ] || fail "exit status 0 after a signal or a failure"; }

# unchanged DIR MESSAGE fails with MESSAGE unless the working directory
# holds what it held before the run.
# shellcheck disable=SC2012 # The names are known and plain.
unchanged() {
	ls -A "$work" | cmp -s - "$1/before" || fail "$2: $(ls -A "$work" | tr '\n' ' ')"
}

# after DIR PORT checks that a run left nothing behind: only the secret in
# the directory, the working directory as it was, and the Caddyfile in it
# unchanged.
# shellcheck disable=SC2012 # The names are known and plain.
after() {
	d=$1 port=$2
	within 10 quiet "$(sid "$d")" || {
		fail "processes left running: $(alive "$(sid "$d")" | tr '\n' ' ')"
		kill -s KILL "-$(sid "$d")" 2>/dev/null
	}
	within 10 free "$port" || fail "port $port still listening"
	got=$(ls -A "$dir" | tr '\n' ' ')
	[ "$got" = "secret " ] || fail "want only secret in the directory, got: $got"
	unchanged "$d" "the working directory changed"
	[ ! -e "$work/Caddyfile" ] || cmp -s "$work/Caddyfile" /src/Caddyfile.example || fail "the Caddyfile changed"
}

# short TICKET succeeds when TICKET is the short form: the endpoint ID and
# one relay URL. It decodes the base32 by hand, since busybox has no base32.
short() {
	printf '%s\n' "$1" | grep -qxE 'endpoint[a-z2-7]+' || return 1
	printf '%s\n' "$1" | awk '{ s = substr($0, 9); bits = 0; k = 0; m = 0
		for (i = 1; i <= length(s); i++) {
			bits = bits * 32 + index("abcdefghijklmnopqrstuvwxyz234567", substr(s, i, 1)) - 1; k += 5
			if (k >= 8) { k -= 8; b = int(bits / 2 ^ k); bits -= b * 2 ^ k; byte[++m] = b } }
		# A variant byte, 32 key bytes, one address, tag 0 (relay URL), length, URL.
		if (byte[1] != 0 || byte[34] != 1 || byte[35] != 0 || m != 36 + byte[36]) exit 1
		url = ""; for (i = 37; i <= 44; i++) url = url sprintf("%c", byte[i])
		exit url != "https://" }'
}

# The first 60 characters of a ticket depend only on the key.
key() { printf '%s' "$1" | cut -c1-60; }
ticket_of() { sed -n 's/^ticket: //p' "$1/out"; }

base=
base=$(listening tcp; listening udp)
dir=$T/a
export DUMBTUNNEL_DIR="$dir"

usage() {
	[ "$(status "$c")" = 2 ] || fail "want exit status 2, got $(status "$c")"
	grep -q 'usage: dumbtunnel' "$c/err" || fail "stderr has no usage line"
	[ ! -s "$c/out" ] || fail "wrote to stdout"
}
start "no arguments and no Caddyfile"
run finish
usage
start "a Caddyfile that does not exist"
run finish "$T/missing"
usage

start "ticket in a new directory"
rm -rf "$dir"
run finish ticket
[ "$(status "$c")" = 0 ] || fail "want exit status 0, got $(status "$c")"
[ "$(grep -c . "$c/out")" = 1 ] || fail "want one line on stdout"
first=$(cat "$c/out")
short "$first" || fail "not a short ticket: $first"
[ "$(grep -cxE '[0-9a-f]{64}' "$dir/secret")" = 1 ] || fail "secret is not 64 lowercase hex digits"
[ "$(grep -c '' "$dir/secret")" = 1 ] || fail "secret is not one line"
[ "$(stat -c %a "$dir/secret")" = 600 ] || fail "secret has mode $(stat -c %a "$dir/secret"), want 600"
after "$c" 8443
cp "$dir/secret" "$T/secret"

start "ticket again"
run finish ticket
[ "$(key "$(cat "$c/out")")" = "$(key "$first")" ] || fail "the endpoint ID changed"
cmp -s "$dir/secret" "$T/secret" || fail "the secret changed"

start "a secret with a trailing newline"
echo >>"$dir/secret"
cp "$dir/secret" "$T/secret"
run finish ticket
[ "$(key "$(cat "$c/out")")" = "$(key "$first")" ] || fail "the endpoint ID changed"
cmp -s "$dir/secret" "$T/secret" || fail "the secret file changed"

start "an empty secret"
export DUMBTUNNEL_DIR="$T/b"
mkdir -p "$T/b" && : >"$T/b/secret"
run finish ticket
grep -qxE '[0-9a-f]{64}' "$T/b/secret" || fail "the empty secret was not replaced"
short "$(cat "$c/out")" || fail "not a short ticket"

start "the default directory"
unset DUMBTUNNEL_DIR
run finish ticket
[ -s "$HOME/.config/dumbtunnel/secret" ] || fail "no secret in \$HOME/.config/dumbtunnel"

start "XDG_CONFIG_HOME"
export XDG_CONFIG_HOME="$T/xdg"
run finish ticket
[ -s "$T/xdg/dumbtunnel/secret" ] || fail "no secret in \$XDG_CONFIG_HOME/dumbtunnel"
unset XDG_CONFIG_HOME
export DUMBTUNNEL_DIR="$dir"

# Caddyfile.example must work as shipped. Caddy reads the CA and the port
# from the environment, so with both unset it must name Let's Encrypt.
start "Caddyfile.example"
(
	unset DUMBTUNNEL_ACME_CA DUMBTUNNEL_PORT
	caddy adapt --config /src/Caddyfile.example --adapter caddyfile 2>/dev/null
) >"$c/json" || fail "caddy adapt failed"
count() { grep -o "$1" "$c/json" | grep -c .; }
issuers=$(count '"issuers":')
[ "$issuers" -ge 1 ] || fail "no certificate issuer"
[ "$(count '"module":"acme"')" = "$issuers" ] || fail "want only the ACME issuer"
[ "$(count '"ca":"https://acme-v02.api.letsencrypt.org/directory"')" = "$issuers" ] || fail "the issuer is not Let's Encrypt"
[ "$(count '"http":{"disabled":true}')" = "$issuers" ] || fail "the HTTP challenge is on"
! grep -qE '"module":"(zerossl|internal)"' "$c/json" || fail "has another issuer"
sed 's/"match":/\n&/g' "$c/json" >"$c/routes"
grep -F '"host":["api.you.duckdns.org"]' "$c/routes" | grep -qF '"dial":"localhost:3000"' ||
	fail "no site api.you.duckdns.org that proxies to localhost:3000"
cp /src/Caddyfile.example "$work/Caddyfile"

# serving DIR PORT checks a running dumbtunnel. stdout holds only the ticket
# line, and Caddy listens on TCP port PORT and nowhere else.
serving() {
	ready "$1" || return
	unchanged "$1" "wrote to the working directory while running"
	within 20 accepts "$2" || fail "nothing accepts on 127.0.0.1:$2"
	within 20 contacted "$1/ca" || fail "Caddy did not contact DUMBTUNNEL_ACME_CA"
	t=$(ticket_of "$1")
	short "$t" || fail "not a short ticket: $t"
	[ "$(key "$t")" = "$(key "$first")" ] || fail "the endpoint ID changed"
	[ "$(grep -c '' "$1/out")" = 1 ] || fail "want only the ticket line on stdout"
	[ "$(listening udp | grep -cx "$2")" = 0 ] || fail "listens on UDP port $2, so HTTP/3 is on"
	[ "$(listening tcp | grep -vx "$caport" | tr '\n' ' ')" = "$2 " ] ||
		fail "want only TCP port $2 listening, got: $(listening tcp | tr '\n' ' ')"
}

s1() { serving "$1" 8443; stop "$1" TERM; }
start "./Caddyfile, then SIGTERM"
run s1
stopped "$c"
after "$c" 8443

# A Caddyfile by any name, relative to the working directory.
s2() { serving "$1" 9443; stop "$1" INT group; }
start "../tunnel.conf, DUMBTUNNEL_PORT=9443, then SIGINT to the group"
cp /src/Caddyfile.example "$T/tunnel.conf"
export DUMBTUNNEL_PORT=9443
run s2 ../tunnel.conf
stopped "$c"
after "$c" 9443

# dumbpipe forwards to 127.0.0.1:DUMBTUNNEL_PORT, and Caddy serves the
# Caddyfile given, not ./Caddyfile.
custom() {
	curl -sS --max-time 5 http://127.0.0.1:7001/ >"$c/got" 2>&1 &&
		[ "$(cat "$c/got")" = "custom Caddyfile on 9444" ]
}
s3() {
	if ! ready "$1"; then
		stop "$1" HUP group
		return
	fi
	dumbpipe connect-tcp --addr 127.0.0.1:7001 "$(ticket_of "$1")" 2>&1 | grep -v 'secret key' >"$1/connect" &
	within 60 custom || fail "through dumbpipe, want the custom page, got: $(cat "$1/got"; tail -n 3 "$1/connect")"
	pkill -f 'connect-tcp --addr 127.0.0.1:7001'
	stop "$1" HUP group
}
start "a custom Caddyfile, then SIGHUP to the group"
export DUMBTUNNEL_PORT=9444
cat >"$T/custom" <<'EOF'
{
	admin off
}

http://:9444 {
	bind 127.0.0.1
	respond "custom Caddyfile on 9444"
}
EOF
run s3 "$T/custom"
stopped "$c"
after "$c" 9444
unset DUMBTUNNEL_PORT

s4() { serving "$1" 8443; stop "$1" HUP; }
start "./Caddyfile, then SIGHUP"
run s4
stopped "$c"
after "$c" 8443

s5() { serving "$1" 8443; stop "$1" INT; }
start "./Caddyfile, then SIGINT"
run s5
stopped "$c"
after "$c" 8443

s6() { serving "$1" 8443; stop "$1" TERM group; }
start "./Caddyfile, then SIGTERM to the group"
run s6
stopped "$c"
after "$c" 8443

# A dumbpipe that fails at once. dumbtunnel must say why, print no ticket,
# start no Caddy and exit.
mkdir "$T/bin"
printf '#!/bin/sh\necho "dumbpipe stand-in failed" >&2\nexit 1\n' >"$T/bin/dumbpipe"
chmod +x "$T/bin/dumbpipe"
broken() {
	path=$PATH
	PATH="$T/bin:$PATH"
	run finish "$@"
	PATH=$path
	[ "$(status "$c")" != 0 ] || fail "exit status 0 when dumbpipe fails"
	[ ! -s "$c/out" ] || fail "wrote to stdout: $(cat "$c/out")"
	grep -q 'dumbpipe stand-in failed' "$c/err" || fail "stderr does not show dumbpipe's error"
	after "$c" 8443
}
start "dumbpipe fails in ticket mode"
broken ticket
start "dumbpipe fails while serving"
broken

start "a broken Caddyfile"
echo 'this is { not a Caddyfile' >"$T/broken"
run finish "$T/broken"
stopped "$c"
after "$c" 8443

if [ -s "$fails" ]; then
	echo "cli: $(wc -l <"$fails") checks failed"
	exit 1
fi
echo "cli: all checks passed"
