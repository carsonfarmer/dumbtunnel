# AGENTS.md

Instructions for coding agents working on dumbtunnel. [README.md](README.md) covers
what the project does and how to use it.

## The project

Two shell scripts and an example Caddyfile that serve a laptop's sites at public
HTTPS names through a relay that sees only encrypted bytes. Nearly all the work is
done by
[dumbpipe](https://github.com/n0-computer/dumbpipe), which moves bytes over iroh, and
[Caddy](https://caddyserver.com), which handles TLS, certificates and routing. This
repository holds the glue.

| Where | What it is |
| --- | --- |
| `dumbtunnel` | The laptop side. It starts dumbpipe and Caddy. |
| `dumbertunnel` | A helper for one site. It writes a Caddyfile and runs `dumbtunnel` on it. It is outside the spec and the suite. |
| `Caddyfile.example` | The user's starting point. Its global block makes Caddy work through the relay. |
| `install.sh` | The relay side. It installs dumbpipe and a systemd service. |
| `.regenerate/` | The spec, the decisions, the rebuild prompt and the spec suite. See its [README](.regenerate/README.md). |
| `test/` | The end-to-end test, in Docker, with Pebble as the CA. The spec suite runs it. |
| `SETUP.md` | The guide an agent follows to set dumbtunnel up with a person. |
| `.github/` | CI for the spec suite, and the Dependabot config. |

## Commands

```bash
test/run.sh                                     # the end-to-end test, in Docker, needs the network
RUST_LOG='warn,iroh=debug' test/run.sh          # the same, with iroh's debug logs
shellcheck dumbtunnel install.sh dumbertunnel test/*.sh
```

Run the end-to-end test and shellcheck before you call a change done. Without a
local shellcheck, run
`docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable` with the same
files.

To try the laptop side on the host, set `DUMBTUNNEL_DIR` and `XDG_DATA_HOME` to
scratch directories, so the run touches neither the real key nor Caddy's data. On
macOS, Go ignores `SSL_CERT_FILE`, so to use the test's Pebble, add `trusted_roots`
to the `cert_issuer` block.

## Plan before you build

For a new feature or any change in behavior, use the
[grill-me](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me)
skill to interview the user before you write code.

## Rules

- **Stay inside the size budget.** `dumbtunnel` and `install.sh` have at most 40 lines
  of code each, counting lines that are neither blank nor comments. CI fails when one
  goes over. When code grows, look in dumbpipe or Caddy for something that already
  does the job.
- **Stay POSIX.** The scripts run under `/bin/sh` on macOS and on busybox. Do not
  use bash features or GNU-only flags. busybox `sed` reads ahead, so do not use it
  on the FIFO.
- **Read the dependency source before you rely on it.** dumbpipe's output, flags and
  environment variables, and Caddy's Caddyfile options, change between releases. Do
  not guess them from memory.
- **Treat the interface as a contract.** Users depend on the command line, the
  environment variables, the stdout of `dumbtunnel` and `dumbtunnel ticket`, the
  file names in `DUMBTUNNEL_DIR`, the global block in `Caddyfile.example`, and the
  `dumbtunnel` systemd unit. `.regenerate/SPEC.md` states them, and the spec suite
  checks them. They change only when the user asks.
- **Leave Caddy config to the user.** dumbtunnel passes the user's Caddyfile to
  Caddy and never writes or checks it. A setting every user needs belongs in the
  global block of `Caddyfile.example`.
- **Keep `dumbertunnel` outside the contract.** It is a helper. The spec, the
  decisions, the spec suite and the size budget do not cover it, and a rebuild
  leaves it alone. It writes its own copy of the first block of
  `Caddyfile.example`, the settings that make Caddy work through the relay, so a
  change to that block goes in both. CI only runs shellcheck on it, so try a change
  to it by hand, in Docker.
- **Keep versions in one place.** The dumbpipe release is named in section 2 of
  `.regenerate/SPEC.md` and in `install.sh`, and the spec suite checks that they
  agree. Image versions live in `test/Dockerfile`, and action versions in the
  workflow files. Do not repeat them anywhere else.
- **Ask before adding a dependency**, on the laptop, on the relay or in CI.
- **Keep the docs in step.** A change in behavior updates the scripts,
  `.regenerate/SPEC.md`, the spec suite, `README.md` and `SETUP.md` together. A new
  design choice gets an entry in `.regenerate/DECISIONS.md`.

## Tests

- The tests run only in Docker, under their own `COMPOSE_PROJECT_NAME`. They must
  never touch containers they did not start, and never run on the host.
- The spec suite looks only at what a user could see, so it can judge a rebuild.
  Check what the scripts do, not how they do it.
- Never loosen a test to make code pass. If a test is wrong, tell the user before you
  change it.
- The tests use Pebble or a stand-in, never a real CA, and the `.test` domain.
- The tests dial through n0's relays and DNS, so they need the network.

## Upstream bugs

Report and fix a bug in dumbpipe, iroh or Caddy upstream. Carry a workaround here
only until the fix is released, and remove it in the commit that updates the
dependency.

## Commits

- Keep commits small. The subject is a short imperative sentence, and the body says
  why.
- Never bypass git hooks with `--no-verify`.
- The `secret` file is a credential, and so is `IROH_SECRET`. Never check one in or
  print it. Do not print dumbpipe's output when it logs a secret key.
- Do not push, tag or open a pull request unless the user asks.

## Writing

Docs and comments use plain, direct prose: short sentences, no em dashes and no hype.
Do not name the maintainer in the docs.
