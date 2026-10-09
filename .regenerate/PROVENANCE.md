# Provenance

This is the provenance record from Chad Fowler's
[Phoenix Primitives](https://aicoding.leaflet.pub/3mjfruwwuck2d): what produced the
reference implementation, and a ledger of every regeneration since.

Anything marked **unknown** was not written down when it happened, and nothing was
filled in from memory. A gap left visible tells the next reader what a rebuild cannot
reproduce.

## The reference implementation

The scripts and `Caddyfile.example` were last changed at commit `3cd5b23`
(2026-10-08). The commits after it add to `.regenerate/` and the docs, and leave the
scripts as they were.

| Item | Value | Source |
| --- | --- | --- |
| Built | 2026-10-08, first commit `fafa33b` | `git log` |
| Model | Claude Opus 5.5, named in the trailer of every commit | commit trailers |
| Harness | Claude Code in the desktop app, one long session | session log, local only |
| Design interview | Multiple-choice questions in the session, not the grill-me skill. The answers: serve both the public and the user's own machines, use stock dumbpipe, take opentunnel.xyz as the reference, run the relay on a free VM, and the name dumbtunnel. | session log, local only |
| Brief | not published | |
| dumbpipe | the release named in `SPEC.md` section 2 and in `install.sh` | `SPEC.md`, `install.sh` |
| Caddy, Pebble, Alpine | the images in `test/Dockerfile` | `test/Dockerfile` |
| Lint | shellcheck at its default severity | `.github/workflows/lint.yml` |
| Live check | One run on an Oracle Cloud Always Free VM (`VM.Standard.E2.1.Micro`, Ubuntu 20.04.6 on x86_64, with `netfilter-persistent`) and a DuckDNS name. Let's Encrypt staging, then production, issued through the relay with TLS-ALPN-01 within seconds. | session log, local only |
| Skill versions, temperature, other model settings | **unknown** | not recorded |

## Changes during the build

Requests and findings during the build session changed the design:

- The relay first got a ticket with only the laptop's ID. Its first dial could reach
  iroh's DNS before the laptop had published, and the cached miss broke dials for
  minutes. The relay now gets the short ticket, which carries the home relay URL.
  This landed before the first commit. See D6 in `DECISIONS.md`.
- dumbtunnel first built its own Caddyfile from `NAME=PORT` arguments and a domain
  variable. Commit `3cd5b23` replaced that with the user's Caddyfile and
  `Caddyfile.example`. See D22.
- A test once ran on the host and overwrote Caddy's saved config. Since then every
  test runs in Docker. See D38.

## Upstream problems found during the build

None of these has a workaround here.

| Problem | Fix | Workaround removed |
| --- | --- | --- |
| On Ctrl-C, dumbpipe `v0.39.0` logs an ERROR that its iroh endpoint was dropped without `Endpoint::close`. | [dumbpipe#98](https://github.com/n0-computer/dumbpipe/pull/98), not released yet | no workaround |
| The relay's dumbpipe logs `WARN dumbpipe: error handling connection: connection lost` often, and does not say why. It may be the race in [dumbpipe#89](https://github.com/n0-computer/dumbpipe/issues/89). | not reported | no workaround |
| On a relay without IPv6, dumbpipe `v0.39.0` logs a `noq_udp` WARN for each send to an IPv6 address. While the laptop is down, it logs `failed closing path err=MultipathNotNegotiated`. | [noq#759](https://github.com/n0-computer/noq/pull/759) and [noq#771](https://github.com/n0-computer/noq/pull/771), not in a dumbpipe release yet | no workaround |

## Regeneration ledger

One row per regeneration attempt, including the ones that failed. A failed row is the
most useful kind, because it points at a gap in `SPEC.md`.

Fill in a row after each check of a rebuild with `check.sh`.

| Date | Mode | Model and harness | Inputs | Result | Spec gaps found | Spec changes |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-10-08 | blind | Claude Sonnet 5.5 (`claude-sonnet-5-5`), as a subagent of Claude Code 2.1.293 in the desktop app. See the notes below. | Reference `4b2ce8d`. Spec, decisions and prompt at `4b2ce8d`. | All four steps passed on the first run: static, cli, relay and e2e. `dumbtunnel` 33 lines of code, `install.sh` 35. The budget was 60 and 40 then. `dumbtunnel` also fits the budget of 40 from `9e52a61`. | None failed. The agent named choices the spec leaves open. See the notes below. | None |

- **Mode** is `blind` or `guided`, as [`README.md`](README.md) defines them.
- **Inputs** names the commit exported as the reference and the commit of `SPEC.md`,
  `DECISIONS.md` and `PROMPT.md` that the run used.
- **Result** says whether each step of `check.sh` passed, names the checks that
  failed, and gives the line counts that the `static` step prints.

### Notes on the runs

**2026-10-08, blind.**

- The prompt was the text of `PROMPT.md`, plus rules from the harness: work only in
  the workspace, test only in Docker under names that start with `regen-`, bind no
  host ports, and read no other copy of dumbtunnel.
- The workspace sat next to the exported reference in one scratch directory. None
  of the agent's 92 tool calls read outside its workspace. It saw the names of the
  suite's `dumbtunnel-*` images in a `docker` listing and did not open them.
- It tested with public images: Alpine, Debian, Caddy and Pebble.
- Choices it made where the spec is open:
  - It stops Caddy with SIGQUIT, because SIGTERM makes Caddy wait for open
    connections.
  - The FIFO is `fifo.PID` in the key directory.
  - A Caddyfile named `ticket` has to be given as `./ticket`.
  - dumbpipe's stdout goes to stderr.
  - The secret is 32 random bytes in hex.
  - `install.sh` puts the iptables rule before the first REJECT rule and adds it
    only once.
  - It downloads with curl, or with wget when curl is missing.
- None of these failed a check, so the spec did not change.
