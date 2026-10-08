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

None of these is reported yet, and none has a workaround here.

| Problem | Fix | Workaround removed |
| --- | --- | --- |
| On Ctrl-C, dumbpipe `v0.39.0` logs an ERROR that its iroh endpoint was dropped without `Endpoint::close`. | not reported | no workaround |
| The relay's dumbpipe logs `WARN dumbpipe: error handling connection: connection lost` for connections that a browser simply closed. | not reported | no workaround |

## Regeneration ledger

One row per regeneration attempt, including the ones that failed. A failed row is the
most useful kind, because it points at a gap in `SPEC.md`.

Fill in a row after each check of a rebuild with `check.sh`.

| Date | Mode | Model and harness | Inputs | Result | Spec gaps found | Spec changes |
| --- | --- | --- | --- | --- | --- | --- |

- **Mode** is `blind` or `guided`, as [`README.md`](README.md) defines them.
- **Inputs** names the commit exported as the reference and the commit of `SPEC.md`,
  `DECISIONS.md` and `PROMPT.md` that the run used.
- **Result** says whether each step of `check.sh` passed, names the checks that
  failed, and gives the line counts that the `static` step prints.
