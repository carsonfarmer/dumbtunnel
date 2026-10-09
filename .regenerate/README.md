# Regenerating dumbtunnel

dumbtunnel is small enough to rebuild from a description. This directory holds that
description, a prompt for the agent that does the rebuilding, and a suite that checks
any implementation against the description. The scripts outside this directory are
one implementation. They are not the only one, and a good rebuild may replace them.

The approach follows Chad Fowler's
[Regenerative Software](https://aicoding.leaflet.pub/3majnyfydzs2y) and
[The Phoenix Primitives](https://aicoding.leaflet.pub/3mjfruwwuck2d), and the
[regenerative software](https://aipatternbook.com/regenerative-software) entry in the
AI pattern book. None of them prescribes a layout, so the files and the two modes
below are this project's own.

## What is kept and what is replaceable

| Kept | Where | Role |
| --- | --- | --- |
| Specification | [`SPEC.md`](SPEC.md) | What the scripts must do. The command line, the environment, stdout, the files, the signals, the relay's service and the example's global block. |
| Decision log | [`DECISIONS.md`](DECISIONS.md) | Why the design is the way it is. It settles what the spec leaves open. |
| Prompt | [`PROMPT.md`](PROMPT.md) | The instructions to give a fresh agent. |
| Spec suite | [`check.sh`](check.sh), [`cli.sh`](cli.sh), [`relay.sh`](relay.sh) and [`../test/`](../test) | Checks an implementation against `SPEC.md`. `static` checks the files, the size budget and shellcheck. `cli` runs `dumbtunnel` through each case in section 6 with the real dumbpipe and Caddy. `relay` runs `install.sh` against the stand-ins in section 7.1. `e2e` sends a request through a relay to a laptop, with a certificate from Pebble. It looks only at what a user could see, so it can judge these scripts or a rebuild, and CI runs it on these. |
| Pins | `SPEC.md` section 2, [`../test/Dockerfile`](../test/Dockerfile) | The dumbpipe release, and the Caddy, Pebble and Alpine images. |
| Provenance | [`PROVENANCE.md`](PROVENANCE.md) | What made the reference, and a ledger of every rebuild. |

The replaceable part is `dumbtunnel` (24 lines of code), `install.sh` (32) and
`Caddyfile.example`. `install.sh` repeats the dumbpipe version from `SPEC.md`, and
`relay.sh` checks that the two agree.

`dumbertunnel`, the one-site helper, is outside all of this. The spec does not
describe it, the suite does not run it, and a rebuild leaves it as it is.

## How fast each part changes

The pattern book asks for named pace layers: how often each layer may change, so that
a rebuild of the implementation does not drag the contract along.

| Layer | What is in it | How often it changes |
| --- | --- | --- |
| Contract | `dumbtunnel [CADDYFILE]` and `dumbtunnel ticket`, the environment variables, the ticket on stdout, the `secret` file, the `dumbtunnel` systemd unit, what the example's global block does, and the spec suite that checks them | Rarely. A change breaks people's setups and relays. |
| Design | `DECISIONS.md`, the size budget, the security model | When someone reopens a decision, and the entry changes with it. |
| Pins | The dumbpipe release in `SPEC.md` and `install.sh`, the images in `test/Dockerfile` | When upstream releases. Dependabot proposes the images. The dumbpipe release is updated by hand. |
| Implementation | `dumbtunnel`, `install.sh`, `Caddyfile.example` | Whenever a rebuild passes the spec suite. |

## Two ways to regenerate

**Blind.** The agent gets `SPEC.md`, `DECISIONS.md`, `PROMPT.md` and `LICENSE`. It
does not get the scripts, the example, `test/` or the spec suite. It can try what it
builds in Docker, with Pebble as the CA. Then you run the spec suite on what it built.
Use this to find out whether the spec is enough. A failure is a spec gap, and the fix
goes into `SPEC.md`.

**Guided.** The agent gets the whole repository, the suite included, and is asked to
rewrite the scripts. Use this for routine work, such as adopting a new dumbpipe
release. The suite does the checking.

## Run it

You need Docker with Compose, the network, and an agent that can edit files and run
commands. From the repository root:

1. Export the reference, here `HEAD`, and make a workspace with the blind inputs:

   ```bash
   ref=$(mktemp -d) ws=$(mktemp -d)
   git archive HEAD | tar -x -C "$ref"
   (cd "$ref" && cp LICENSE .regenerate/SPEC.md .regenerate/DECISIONS.md \
     .regenerate/PROMPT.md "$ws/")
   ```

   For a guided run, copy all of `$ref` into `$ws` instead.
2. Start a fresh agent session in `$ws`. Give it the text of `PROMPT.md`, and tell
   it to work only inside `$ws`.
3. When it reports, check the result, whatever the agent says about it. Put its
   files in place of the reference's and run the suite:

   ```bash
   cp "$ws/dumbtunnel" "$ws/install.sh" "$ws/Caddyfile.example" "$ref/"
   COMPOSE_PROJECT_NAME=dumbtunnel-regen "$ref/.regenerate/check.sh"
   ```

   The `static` step prints the line counts for the ledger. The suite builds its
   image from the candidate's own `install.sh`, so a rebuild that cannot install
   dumbpipe fails every step after `static`.
4. Try the rebuild on macOS by hand, since the suite runs on busybox. Section 11 of
   `SPEC.md` lists what else the suite leaves out.
5. Add a row to the ledger in [`PROVENANCE.md`](PROVENANCE.md). Record failures too.

## Rules for a fair run

- **Do not loosen the spec suite or fix the candidate by hand to make a rebuild pass.**
  Change the spec, then run the rebuild again.
- **Keep the agent away from the existing implementation.** A blind run only means
  something if the agent never saw the scripts. Copies sit in this checkout, in any
  clone, and in the images the suite builds, which are named after their
  `COMPOSE_PROJECT_NAME`. An agent with a shell can still read outside its workspace,
  so for a run that must hold up, use a machine or container with no other copy.
- **Record what the run used.** Model, harness, prompt and spec versions go in the
  ledger. Without them, nobody can tell one run from another.

## What a passing run shows

A rebuild that passes the spec suite has the same command line, the same stdout, the
same exit statuses, the same signal handling, the same relay service and the same
global settings as the reference, as far as the suite reaches. It also serves a site
through a relay with a certificate from an ACME CA. `SPEC.md` lists, in section 11,
what the suite does not reach. The badge in the README points here so a reader can
check the last ledger row and decide how much that run proves.

## Working on the suite

- `check.sh` runs all four steps. Name steps to run only those, such as
  `check.sh static cli`.
- A change in behavior updates `SPEC.md` and the suite with the scripts. A new
  design choice gets an entry in `DECISIONS.md`. A new dumbpipe release goes in
  `SPEC.md` and `install.sh`.
- Everything but `static` runs in Docker, in the image from `test/Dockerfile`, under
  `COMPOSE_PROJECT_NAME`. It defaults to `dumbtunnel-check`. Give each concurrent run
  its own name, and never run the suite on the host.
- The suite never contacts a real CA. `cli` points `DUMBTUNNEL_ACME_CA` at a listener
  that only records that Caddy called it, and `e2e` uses Pebble.
- Each check names what a user would see, not how the reference does it. A check of
  how would fail a rebuild that is correct.
- When you add a check, break the scripts on purpose, one way at a time, and see the
  suite fail. A check that passes on a broken script is not checking anything.
