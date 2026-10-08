# Regenerate dumbtunnel

You are rebuilding a small shell project from its specification. You have not seen
the existing implementation and you must not look for it. Someone will check your
result against tests you cannot see.

## Your inputs

The workspace holds:

- `SPEC.md`. The behavior the result must have. It is your source of truth.
- `DECISIONS.md`. Why the design is the way it is. Use it to choose between options
  when `SPEC.md` leaves room.
- `LICENSE`. Keep it as it is.

## What to produce

1. `dumbtunnel`, the laptop script, executable.
2. `install.sh`, the relay script.
3. `Caddyfile.example`, the user's starting point.

Nothing else. No README, no tests in the workspace, no CI files.

## How to work

1. Read `SPEC.md` and `DECISIONS.md` in full before writing anything.
2. Read the source of what you call before you rely on it. dumbpipe's output, flags
   and environment variables are in `src/main.rs` at the release tag that `SPEC.md`
   names, at `github.com/n0-computer/dumbpipe`. For Caddy, read its documentation at
   `caddyserver.com/docs` or its source at `github.com/caddyserver/caddy`. Do not
   guess them from memory.
3. Write the smallest scripts that satisfy `SPEC.md`. The goal is the fewest custom
   lines. `dumbtunnel` must stay within 60 lines of code and `install.sh` within 40,
   counted as section 2 of the spec says. dumbpipe and Caddy do the real work. If a
   script is getting long, look in them for something that does the job.
4. Write POSIX `sh` that runs under macOS `/bin/sh`, dash and busybox `ash`. No bash
   features and no GNU-only flags. Comment the reason for anything surprising. Do
   not comment the obvious.
5. Run `shellcheck` on both scripts as you go. Without a local copy, use the
   `koalaman/shellcheck:stable` Docker image.
6. Try what you built. Run it in a container, where you can install dumbpipe with
   your own `install.sh` and Caddy from its official image. On a host, set
   `DUMBTUNNEL_DIR`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME` to scratch directories, so
   the run touches neither a real key nor Caddy's data.

## What you must not do

- Read any other copy of this project, including one in a parent directory, a sibling
  directory, a container image or a git remote. If you find one, close it and tell me
  in your report.
- Contact a real certificate authority, Let's Encrypt staging included. For
  certificates, use Pebble, Let's Encrypt's test CA, in a container. Otherwise try
  Caddyfiles without automatic HTTPS, or check the example with `caddy adapt`.
- Create accounts, cloud resources or DNS records. Bind ports below 1024 on the host.
- Print a secret key. dumbpipe prints one when `IROH_SECRET` is unset. Filter that
  line out of anything you show.

## Tests (held out)

A spec suite, which I am not showing you, decides whether your rebuild is kept:

- It is held out on purpose. If you had it, you could fit the scripts to the tests
  and stop reading the spec closely. The point of this exercise is to find out
  whether `SPEC.md` is enough to build the project. A rebuild that passes tests it
  was shown proves less.
- It checks the first line, the size budget and shellcheck. It then runs your
  scripts by name in an Alpine image: `dumbtunnel` with the real dumbpipe and Caddy,
  through each signal and failure in section 6, and `install.sh` with the stand-ins
  in section 7.1. Last, it runs the whole path in Docker with Pebble, through a relay.
- The image installs dumbpipe by running your `install.sh` with no ticket. If that
  fails, every test fails.
- It reads the files and the strings that sections 6, 9 and 10 name, so the spec
  fixes those exactly.
- If the suite fails, the spec gets fixed. The tests do not get loosened.

## Where the spec is silent

`SPEC.md` is not perfect. When it says nothing, or two sections disagree, choose the
smallest behavior that fits `DECISIONS.md` and the tools involved, and write it down.
Do not stop to ask.

## When you finish

Reply with a short report and nothing else:

1. The files you wrote, with the code line count of each script.
2. The output of `shellcheck`, and what you ran to try the scripts, with the result.
3. Every place `SPEC.md` was silent, vague or contradictory, and what you chose.
4. Anything you read outside the workspace, dumbpipe and Caddy.
5. Anything in your scripts you are unsure about.

Do not commit and do not push.
