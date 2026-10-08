#!/bin/sh
# relay.sh checks install.sh against SPEC.md, section 7. check.sh runs it as
# root in the test image, with the repository at /src. Stand-ins for
# systemctl, netfilter-persistent and iptables log their calls, and the fake
# iptables starts with the INPUT chain of Oracle's Ubuntu images.
set -u

# Public tickets made from throwaway keys.
t1=endpointadn55pjj2cnbhcflq2q2n6nhjc4u5z5fs42n5fslvrhqxhd3wsoz2aiaenuhi5dqom5c6l3von3tcljrfzzgk3dbpexg4mbonfzg62bonruw42zof4
t2=endpointacflathki7xxogvra64j454y5alfd6yesejnvrq25mrofsepk4v7saiaenuhi5dqom5c6l3von3tcljrfzzgk3dbpexg4mbonfzg62bonruw42zof4
unit=/etc/systemd/system/dumbtunnel.service
bin=/usr/local/bin/dumbpipe

T=$(mktemp -d)
export STUBS="$T/stubs"
mkdir -p "$STUBS/bin" /etc/systemd/system
PATH="$STUBS/bin:$PATH"
calls=$STUBS/calls
rules=$STUBS/rules
fails=0
fail() {
	echo "FAIL: $step: $*" >&2
	fails=$((fails + 1))
}

# shellcheck disable=SC2016 # The stand-ins expand these.
for cmd in systemctl netfilter-persistent; do
	printf '#!/bin/sh\necho "%s $*" >>"$STUBS/calls"\n' "$cmd" >"$STUBS/bin/$cmd"
done
cat >"$STUBS/bin/iptables" <<'EOF'
#!/bin/sh
# A stand-in for iptables. It keeps the INPUT chain of the filter table in a
# file and understands -C, -I, -A, -D and -S, with -w and -t filter.
echo "iptables $*" >>"$STUBS/calls"
rules=$STUBS/rules
while :; do
	case ${1:-} in
	-w | --wait) shift && case ${1:-} in [0-9]*) shift ;; esac ;;
	-t | --table) [ "${2:-}" = filter ] || exit 2 && shift 2 ;;
	*) break ;;
	esac
done
op=${1:-} chain=${2:-}
case $op in -S | --list-rules)
	[ -z "$chain" ] || [ "$chain" = INPUT ] || exit 1
	echo "-P INPUT ACCEPT" && sed 's/^/-A INPUT /' "$rules"
	exit
	;;
esac
[ "$chain" = INPUT ] || { echo "iptables stand-in: only the INPUT chain" >&2 && exit 2; }
shift 2
n=$(wc -l <"$rules")
case $op in
-C | --check) grep -qxF -- "$*" "$rules" || { echo "iptables: Bad rule (does a matching rule exist in that chain?)." >&2 && exit 1; } ;;
-A | --append) echo "$*" >>"$rules" ;;
-I | --insert)
	at=1
	case ${1:-} in [0-9]*) at=$1 && shift ;; esac
	[ "$at" -ge 1 ] && [ "$at" -le $((n + 1)) ] || { echo "iptables: Index of insertion too big." >&2 && exit 1; }
	awk -v at="$at" -v r="$*" 'NR == at { print r } { print } END { if (at == NR + 1) print r }' "$rules" >"$rules.new"
	mv "$rules.new" "$rules"
	;;
-D | --delete)
	case ${1:-} in
	[0-9]*) at=$1 ;;
	*) at=$(grep -nxF -- "$*" "$rules" | head -n 1 | cut -d: -f1) ;;
	esac
	[ -n "$at" ] && [ "$at" -le "$n" ] || { echo "iptables: Bad rule (does a matching rule exist in that chain?)." >&2 && exit 1; }
	sed "${at}d" "$rules" >"$rules.new" && mv "$rules.new" "$rules"
	;;
*) echo "iptables stand-in: $op is not supported" >&2 && exit 2 ;;
esac
EOF
chmod +x "$STUBS/bin/"*
cat >"$rules" <<'EOF'
-m state --state RELATED,ESTABLISHED -j ACCEPT
-p icmp -j ACCEPT
-i lo -j ACCEPT
-p udp -m udp --sport 123 -j ACCEPT
-p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-j REJECT --reject-with icmp-host-prohibited
EOF

# install TICKET runs install.sh the way SETUP.md does, from stdin.
install() {
	: >"$calls"
	sh -s -- "$@" </src/install.sh >"$T/out" 2>"$T/err" || fail "exit status $?: $(tail -n 5 "$T/err")"
}

called() { grep -q "^$1" "$calls"; }

# has WORD ARGS... succeeds when WORD is one of ARGS.
has() {
	w=$1
	shift
	for a; do [ "$a" = "$w" ] && return 0; done
	return 1
}

# systemctl must reload the units, then enable and restart dumbtunnel.
started() {
	awk '$1 == "systemctl" && $2 == "daemon-reload" { reload = 1 }
		$1 == "systemctl" { e = r = u = 0
			for (i = 2; i <= NF; i++) {
				if ($i == "enable") e = 1
				if ($i == "restart" || $i == "reload-or-restart") r = 1
				if ($i == "dumbtunnel" || $i == "dumbtunnel.service") u = 1 }
			if (u && e) enabled = 1
			if (u && r && reload) restarted = 1 }
		END { exit !(enabled && restarted) }' "$calls" ||
		fail "want systemctl daemon-reload, then enable and restart of dumbtunnel. Got: $(grep systemctl "$calls" | tr '\n' ';')"
}

# Port 443 must be open once, before Oracle's REJECT rule.
opened() {
	awk '/(^| )-p tcp( |$)/ && /(^| )--dport 443( |$)/ && /(^| )-j ACCEPT( |$)/ { n++; if (!reject) before++ }
		/(^| )-j REJECT( |$)/ { reject = 1 }
		END { exit !(n == 1 && before == 1) }' "$rules" ||
		fail "want one ACCEPT rule for TCP port 443 before the REJECT rule. Got: $(tr '\n' ';' <"$rules")"
}

# The binary must be the official release named in SPEC.md.
step="install dumbpipe"
# shellcheck disable=SC2016 # The backquotes are Markdown.
version=$(sed -n 's/^| dumbpipe | `\(v[^`]*\)`.*/\1/p' /src/.regenerate/SPEC.md)
arch=$(uname -m)
[ -n "$version" ] || fail "no dumbpipe version in SPEC.md"
mkdir "$T/release"
curl -fsSL "https://github.com/n0-computer/dumbpipe/releases/download/$version/dumbpipe-$version-linux-$arch.tar.gz" |
	tar -xz -C "$T/release" || fail "cannot download dumbpipe $version"
rm -f "$bin"
install
[ -x "$bin" ] || fail "$bin is missing or not executable"
cmp -s "$bin" "$T/release/dumbpipe" || fail "$bin is not the $version release"
[ ! -e "$unit" ] || fail "made $unit without a ticket"
! called systemctl || fail "called systemctl without a ticket"
! called iptables || fail "called iptables without a ticket"

step="ticket"
install "$t1"
if [ -f "$unit" ]; then
	start=$(sed -n 's/^ExecStart=//p' "$unit")
	[ "$(printf '%s\n' "$start" | grep -c .)" -eq 1 ] || fail "want one ExecStart line, got: $start"
	eval "set -- $(printf '%s' "$start" | sed 's/^[-@:+!]*//')"
	case ${1:-} in /*) ;; *) fail "ExecStart does not start with an absolute path: $start" ;; esac
	has connect-tcp "$@" || fail "ExecStart does not run connect-tcp: $start"
	has "$t1" "$@" || fail "ExecStart does not pass the ticket as one argument: $start"
	grep -qixE 'DynamicUser=(yes|true|on|1)' "$unit" ||
		{ grep -qE '^User=' "$unit" && ! grep -qxE 'User=(root|0)' "$unit"; } ||
		fail "the service runs as root"
	grep -qE '^AmbientCapabilities=.*CAP_NET_BIND_SERVICE' "$unit" || fail "no AmbientCapabilities=CAP_NET_BIND_SERVICE"
	if ! grep -qE '^Restart=' "$unit" || grep -qxE 'Restart=no' "$unit"; then
		fail "the service does not restart"
	fi
	grep -qE '^WantedBy=.*multi-user\.target' "$unit" || fail "not WantedBy=multi-user.target"
else
	fail "no $unit"
fi

started
opened
called "netfilter-persistent save" || fail "did not run netfilter-persistent save"

step="ticket again"
install "$t1"
opened
started

step="new ticket"
install "$t2"
grep -qF "$t2" "$unit" || fail "the unit does not have the new ticket"
! grep -qF "$t1" "$unit" || fail "the unit still has the old ticket"
started

step="no netfilter-persistent"
rm "$STUBS/bin/netfilter-persistent"
install "$t1"
! called iptables || fail "called iptables without netfilter-persistent"

# Run the ExecStart line for real. dumbpipe waits up to 5 seconds to come
# online before it binds.
step="relay listens"
eval "set -- $(sed -n 's/^ExecStart=//p' "$unit" | sed 's/^[-@:+!]*//')"
"$@" >/dev/null 2>&1 &
relay=$!
i=0
until netstat -ltn | awk '{ print $4 }' | grep -qxE '(0\.0\.0\.0|::):443'; do
	i=$((i + 1))
	[ $i -lt 30 ] || {
		fail "nothing listens on TCP port 443 on all interfaces"
		break
	}
	sleep 1
done
kill "$relay" 2>/dev/null

if [ $fails -gt 0 ]; then
	echo "relay: $fails checks failed"
	exit 1
fi
echo "relay: all checks passed"
