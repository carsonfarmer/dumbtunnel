#!/bin/sh
# check.sh judges dumbtunnel and install.sh against SPEC.md.
#
#   .regenerate/check.sh               # every step
#   .regenerate/check.sh static cli    # only these steps
#
# static checks the files and needs shellcheck or Docker. cli, relay and e2e
# run in the test image and need Docker and the network.
set -u
cd "$(dirname "$0")/.." || exit
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dumbtunnel-check}"
[ $# -gt 0 ] || set -- static cli relay e2e

compose() { docker compose -f test/compose.yaml "$@"; }

static() {
	ok=0
	for f in dumbtunnel install.sh; do
		[ "$(head -n 1 "$f" 2>/dev/null)" = '#!/bin/sh' ] || { echo "$f: the first line is not #!/bin/sh" && ok=1; }
	done
	[ -x dumbtunnel ] || { echo "dumbtunnel is not executable" && ok=1; }
	# Counts lines that are neither blank nor comments.
	for budget in dumbtunnel:60 install.sh:40; do
		f=${budget%:*} max=${budget#*:}
		lines=$(grep -cvE '^[[:space:]]*(#|$)' "$f")
		echo "$f: $lines of $max lines"
		[ "$lines" -le "$max" ] || ok=1
	done
	if command -v shellcheck >/dev/null; then
		shellcheck dumbtunnel install.sh || ok=1
	else
		docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable dumbtunnel install.sh || ok=1
	fi
	return $ok
}

in_image() { compose run --rm --no-deps -T -v "$PWD:/src:ro" "$1" sh "/src/.regenerate/$2"; }
cli() { in_image laptop cli.sh; }
relay() { in_image relay relay.sh; }
e2e() { test/run.sh; }

for step; do
	case $step in
	static | cli | relay | e2e) ;;
	*) echo "usage: .regenerate/check.sh [static|cli|relay|e2e]..." >&2 && exit 2 ;;
	esac
done
case " $* " in *" cli "* | *" relay "*)
	trap 'compose down -v -t 1 >/dev/null 2>&1' EXIT
	compose build -q || exit 1
	;;
esac

failed=
for step; do
	echo "### $step"
	"$step" || failed="$failed $step"
done
if [ -n "$failed" ]; then
	echo "### failed:$failed"
	exit 1
fi
echo "### passed: $*"
