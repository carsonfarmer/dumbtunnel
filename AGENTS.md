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
| `Caddyfile.example` | The user's starting point. Its global block makes Caddy work through the relay. |
| `install.sh` | The relay side. It installs dumbpipe and a systemd service. |
| `test/` | The end-to-end test, in Docker, with Pebble as the CA. |
| `.github/` | CI for the test, shellcheck and the size budget, and the Dependabot config. |

## Commands

```bash
test/run.sh                                  # the end-to-end test, needs the network
RUST_LOG='warn,iroh=debug' test/run.sh       # the same, with iroh's debug logs
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable dumbtunnel install.sh test/*.sh
```

Run shellcheck and the end-to-end test before you call a change done. The test runs
in Docker. To try the laptop side on the host, set `DUMBTUNNEL_DIR` and
`XDG_DATA_HOME` to scratch directories, so the run touches neither the real key nor
Caddy's data. On macOS, Go ignores `SSL_CERT_FILE`, so to use the test's Pebble, add
`trusted_roots` to the `cert_issuer` block.

## Plan before you build

For a new feature or any change in behavior, use the
[grill-me](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me)
skill to interview the user before you write code.

## Rules

- **Stay inside the size budget.** `dumbtunnel` stays under 60 lines of code and
  `install.sh` under 40, counting lines that are neither blank nor comments. CI fails
  when one goes over. When code grows, look in dumbpipe or Caddy for something that
  already does the job.
- **Stay POSIX.** The scripts run under `/bin/sh` on macOS and on busybox. Do not
  use bash features or GNU-only flags. busybox `sed` reads ahead, so do not use it
  on the FIFO.
- **Read the dependency source before you rely on it.** dumbpipe's output, flags and
  environment variables, and Caddy's Caddyfile options, change between releases. Do
  not guess them from memory.
- **Treat the interface as a contract.** Users depend on the command line, the
  environment variables, the stdout of `dumbtunnel` and `dumbtunnel ticket`, the
  file names in `DUMBTUNNEL_DIR`, the global block in `Caddyfile.example`, and the
  `dumbtunnel` systemd unit. They change only when the user asks.
- **Leave Caddy config to the user.** dumbtunnel passes the user's Caddyfile to
  Caddy and never writes or checks it. A setting every user needs belongs in the
  global block of `Caddyfile.example`.
- **Keep versions in one place.** The dumbpipe version lives in `install.sh`, image
  versions in `test/Dockerfile`, and action versions in the workflow files. Do not
  repeat them in docs, comments or tests.
- **Ask before adding a dependency**, on the laptop, on the relay or in CI.
- **Keep the docs in step.** A change in behavior updates the scripts, the test and
  `README.md` together.

## Tests

- The test runs only in Docker, under its own `COMPOSE_PROJECT_NAME`. It must never
  touch containers it did not start.
- Never loosen a test to make code pass. If a test is wrong, tell the user before you
  change it.
- The test uses Pebble, never a real CA, and the `.test` domain.
- The test dials through n0's relays and DNS, so it needs the network.

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
