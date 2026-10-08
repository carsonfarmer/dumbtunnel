# dumbtunnel specification

This file states what dumbtunnel must do. MUST, SHOULD and MAY are used as in
RFC 2119.

It was written from the reference scripts, the README, the end-to-end test and a
live setup on an Oracle VM with a DuckDNS name. It describes the reference as it is.
`PROVENANCE.md` names the commits.

A blind rebuild (see `PROMPT.md`) gets this file, `DECISIONS.md`, `PROMPT.md` and
`LICENSE`, and nothing else from the repository. If a rebuild fails the suite because
this file was silent or vague, fix this file and run the rebuild again.

## 1. Purpose

Serve sites from a laptop at public HTTPS names, through a relay that sees only
encrypted bytes.

- The **relay** is a Linux VM with a public IPv4 address. It runs stock
  `dumbpipe connect-tcp`, which accepts TCP connections on port 443 and sends each
  one over iroh to the laptop. It holds no certificate and decrypts nothing.
- The **laptop** runs `dumbpipe listen-tcp`, which hands each connection to Caddy.
  Caddy ends TLS, gets certificates from Let's Encrypt, and serves the sites in the
  user's Caddyfile, such as a reverse proxy to a local port.

dumbtunnel is `caddy run`, reachable from the internet through a server that cannot
read the traffic. The deliverable is two POSIX shell scripts, `dumbtunnel` for the
laptop and `install.sh` for the relay, and `Caddyfile.example`, the starting point
for the user's Caddyfile. All the real work is done by dumbpipe and Caddy.

## 2. Inputs that are fixed

| Item | Value |
| --- | --- |
| dumbpipe | `v0.39.0`, the official release binaries from `github.com/n0-computer/dumbpipe` |
| Caddy | 2.11 or later, as `caddy` on `PATH` |
| Shell | POSIX `sh`. The scripts MUST run under macOS `/bin/sh`, dash and busybox `ash`. |
| Files | `dumbtunnel`, which is executable, `install.sh` and `Caddyfile.example`. Each script starts with the line `#!/bin/sh`. |
| Size | `dumbtunnel` and `install.sh` at most 40 lines of code each |
| Lint | shellcheck, with no findings at its default severity |
| License | MIT (unchanged) |

A line of code is a line that is neither blank nor a comment. The count is
`grep -cvE '^[[:space:]]*(#|$)' FILE`, so lines inside a here-document count too.

The laptop uses the `dumbpipe` and `caddy` on its `PATH`. `install.sh` installs
dumbpipe at the version above, and the suite checks that it installed exactly that
release.

The scripts MUST NOT need anything beyond dumbpipe, Caddy and the tools that macOS,
Ubuntu and busybox all have. They MUST NOT use bash features or GNU-only flags.

## 3. Definitions

- **Secret.** The laptop's iroh secret key: 32 random bytes, written as 64 lowercase
  hex characters. dumbpipe reads it from the environment variable `IROH_SECRET`.
- **Endpoint ID.** The public key that goes with the secret. It is the laptop's
  address on iroh.
- **Ticket.** A string that tells dumbpipe how to reach an endpoint. It is
  `endpoint` followed by lowercase, unpadded base32 of the ticket's bytes: a variant
  byte, the 32 bytes of the endpoint ID, then a list of addresses. The first 60
  characters depend only on the endpoint ID.
- **Short ticket.** A ticket whose address list holds exactly one relay URL, the
  laptop's iroh home relay, and nothing else. dumbtunnel always uses the short form.
  See section 6.7 for where it comes from.
- **Directory.** `DUMBTUNNEL_DIR`. When that is unset, `$XDG_CONFIG_HOME/dumbtunnel`,
  and when that is unset too, `$HOME/.config/dumbtunnel`.
- **Port.** `DUMBTUNNEL_PORT`, `8443` when unset. dumbpipe forwards to `127.0.0.1`
  at that port, and the example Caddyfile serves HTTPS there.
- **Caddyfile.** The Caddy configuration that dumbtunnel serves: the file named on
  its command line, or `Caddyfile` in the current directory. It belongs to the user,
  who makes it from `Caddyfile.example`.

## 4. The path

```text
browser ──TLS──▶ relay :443 ──iroh──▶ dumbpipe listen-tcp ──▶ Caddy 127.0.0.1:PORT ──▶ target
```

- The relay forwards raw TCP. TLS runs from the browser to Caddy on the laptop.
- Caddy proves control of each name with the TLS-ALPN-01 challenge. The CA's
  validation connects to port 443 of the name, which is the relay, and reaches Caddy
  like any other connection. No port 80 and no DNS API are involved.
- The relay finds the laptop with the short ticket. The relay URL in it lets the
  relay connect before iroh's DNS has published the laptop's address. After that,
  iroh finds the laptop by its endpoint ID even if its home relay changes.
- Every name in the Caddyfile points at the relay's IPv4 address. Setting that up is
  outside the scripts.

## 5. Caddyfile.example

dumbtunnel runs Caddy with the user's Caddyfile, through Caddy's Caddyfile adapter.
It does not write, check or change that file. `Caddyfile.example` is where the user
starts. Caddy MUST accept it unchanged, and served unchanged it MUST give this
configuration:

1. **No admin endpoint.** Nothing listens on Caddy's admin port.
2. **HTTPS on the port.** Caddy MUST accept TLS connections on `127.0.0.1:PORT` and
   answer the TLS-ALPN-01 challenge there. It MAY listen on all interfaces.
3. **Nothing else listens.** No HTTP server, nothing on port 80, no redirects from
   HTTP to HTTPS. While dumbtunnel runs, the port is the only TCP port Caddy opens.
4. **HTTP/1.1 and HTTP/2 only.** No HTTP/3, so Caddy opens no UDP socket on the port.
5. **One certificate issuer.** Every certificate comes from the ACME directory in
   `DUMBTUNNEL_ACME_CA`, which defaults to Let's Encrypt production,
   `https://acme-v02.api.letsencrypt.org/directory`. There is no ZeroSSL issuer and
   no internal issuer. The HTTP-01 challenge is disabled, and no DNS challenge is
   set, so TLS-ALPN-01 is the only one left.
6. **One sample site.** `api.you.duckdns.org`, a reverse proxy to `localhost:3000`.
   More samples MAY appear in comments.
7. **The CA and the port come from the environment when Caddy starts.** The file
   reads `DUMBTUNNEL_ACME_CA` and `DUMBTUNNEL_PORT` through Caddy's `{$VAR:default}`
   placeholders, with the defaults above.

Rules 1 to 5 and 7 live in one global options block. A comment MUST tell the user to
copy the file to `Caddyfile`, change the sites to their own, and keep that block.

Caddy keeps certificates and its ACME account in its default data directory.
dumbtunnel does not change where that is.

## 6. dumbtunnel

### 6.1 Synopsis

```text
dumbtunnel [CADDYFILE]   serve the sites in CADDYFILE, ./Caddyfile by default
dumbtunnel ticket        print the ticket and exit
```

### 6.2 Every mode

Once the arguments are accepted (6.3), and before dumbpipe starts:

1. Create the directory, with its parents, if it does not exist.
2. If `secret` in the directory is missing or empty, write a new secret to it from
   `/dev/urandom`. A file that dumbtunnel creates MUST have mode `600`. A trailing
   newline is optional.
3. Never replace a secret that is not empty. When reading it, ignore a trailing
   newline, so that a file saved by an editor keeps the same identity.
4. Pass the secret to dumbpipe only through `IROH_SECRET` in dumbpipe's
   environment. Never print it and never put it on a command line. Without
   `IROH_SECRET`, dumbpipe makes a new key and prints it, which MUST NOT happen.

### 6.3 Arguments

- **`ticket`** as the first argument selects ticket mode (6.5). Later arguments MAY
  be ignored. To serve a Caddyfile named `ticket`, give it as `./ticket`.
- **Anything else** is the path of the Caddyfile, relative to the current directory.
  With no argument it is `Caddyfile`. Later arguments MAY be ignored.
- If no regular file is at that path, write a usage line that starts with
  `usage: dumbtunnel` to stderr and exit with status 2, with nothing on stdout and
  before starting anything. Otherwise serve (6.4) with that file. Caddy reads it as a
  Caddyfile, whatever its name.

### 6.4 Serving

1. Start `dumbpipe listen-tcp`, forwarding to `127.0.0.1:PORT`, with the secret.
2. Wait for dumbpipe to give the short ticket (6.7), then print `ticket: TICKET` on
   stdout.
3. Start Caddy with the Caddyfile, through its Caddyfile adapter. Caddy SHOULD start
   only after step 2, so that its first certificate challenge can reach the laptop.
4. Keep running. dumbpipe's and Caddy's logs go to stderr.

stdout carries only the ticket line. Everything else goes to stderr.

If dumbpipe exits before it gives the ticket, for example because it is not on
`PATH`, dumbtunnel MUST exit with a nonzero status, print no ticket line, and not
start Caddy. What dumbpipe wrote before it exited, such as its error, MUST appear on
stderr.

dumbtunnel stops on SIGHUP, SIGINT or SIGTERM, whether the signal goes to dumbtunnel
alone or to its whole process group. It also stops when Caddy exits, such as when the
Caddyfile is broken. When it stops, it MUST:

- stop dumbpipe and Caddy, and anything else it started;
- remove any file it made in the directory besides `secret`, and leave the current
  directory and the Caddyfile as they were;
- exit with a nonzero status. The reference exits with 129 on SIGHUP, and 130 on
  SIGINT and SIGTERM.

Within 10 seconds of the signal, nothing it started is left running and the port is
free. Caddy ignores SIGHUP, so dumbtunnel has to stop it itself.

### 6.5 Ticket mode

Start dumbpipe as in 6.4, wait for the short ticket, and print exactly the ticket on
one line on stdout, with no prefix. Then stop dumbpipe and exit with status 0. Do not
start Caddy. Ticket mode needs no Caddyfile. Afterward nothing is left running, and
the directory holds only what it held before plus `secret`. If dumbpipe exits first,
fail as in 6.4, with nothing on stdout.

### 6.6 Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `DUMBTUNNEL_DIR` | see section 3 | Where `secret` lives. |
| `DUMBTUNNEL_PORT` | `8443` | Where dumbpipe forwards, on `127.0.0.1`. The example Caddyfile serves HTTPS there. |
| `DUMBTUNNEL_ACME_CA` | Let's Encrypt production | The ACME directory URL. The example Caddyfile reads it when Caddy starts. dumbtunnel does not read it. |

### 6.7 What dumbpipe gives

These facts about dumbpipe `v0.39.0` come from its `src/main.rs`.

- `IROH_SECRET` sets the key, as hex. When it is unset, dumbpipe makes a new key and
  prints it to stderr as `using secret key HEX`.
- `dumbpipe listen-tcp --host HOST:PORT` forwards each incoming iroh connection to
  `HOST:PORT` over TCP.
- It waits up to 5 seconds for its endpoint to be online. If that times out, it
  prints `Warning: Failed to connect to the home relay` and goes on.
- Then it writes these lines to stderr. The last two appear only with `-v`:

  ```text
  Forwarding incoming requests to 'HOST:PORT'.
  To connect, use e.g.:
  dumbpipe connect-tcp LONG_TICKET
  or:
  dumbpipe connect-tcp SHORT_TICKET
  ```

  The long ticket also lists the laptop's current IP addresses, which go stale when
  it moves. The short ticket is the third word of the line after `or:`.
- dumbpipe keeps stderr open and logs to it later.
- `dumbpipe connect-tcp --addr ADDR TICKET` waits the same 5 seconds for its own
  endpoint, then listens on `ADDR` and sends each TCP connection to the ticket's
  endpoint.

## 7. install.sh

`install.sh` runs as root on the relay, in either of these ways. It MUST NOT depend
on its own path.

```text
sh install.sh [TICKET]
ssh ubuntu@VM_IP 'sudo sh -s -- TICKET' < install.sh
```

1. **Install dumbpipe**, every time. Download the official release
   `dumbpipe-VERSION-OS-ARCH.tar.gz` from
   `https://github.com/n0-computer/dumbpipe/releases/download/VERSION/`, where
   VERSION is the one in section 2, OS is `linux` or `darwin` and ARCH is `x86_64` or
   `aarch64`. Note that `uname -m` says `arm64` on macOS. The archive holds
   `./dumbpipe`. Put it at `/usr/local/bin/dumbpipe`, replacing any binary there,
   and make it executable.
2. **Without a ticket**, stop there and exit with status 0. Write no unit and call
   neither `systemctl` nor `iptables`. This mode installs dumbpipe on a Linux laptop
   and in the test image.
3. **With a ticket**, write `/etc/systemd/system/dumbtunnel.service`, replacing any
   that exists:
   - one `ExecStart=` line that runs `/usr/local/bin/dumbpipe connect-tcp`, listens
     on `0.0.0.0:443`, and passes the ticket as one argument;
   - the service does not run as root: `DynamicUser=yes`, or `User=` naming another
     user;
   - `AmbientCapabilities=CAP_NET_BIND_SERVICE`, so it can bind port 443;
   - a `Restart=` setting other than `no`;
   - `WantedBy=multi-user.target` in `[Install]`.

   It SHOULD start after `network-online.target` and set `RUST_LOG=warn`, to keep
   the journal quiet.
4. **Open the firewall on Oracle.** If and only if `netfilter-persistent` is on
   `PATH`, make sure the `INPUT` chain has exactly one rule that accepts TCP port
   443, placed before the final `REJECT` rule. Add it only when it is missing. Then
   run `netfilter-persistent save`. Without `netfilter-persistent`, MUST NOT call
   `iptables`.
5. **Start it.** Run `systemctl daemon-reload`, then `systemctl enable dumbtunnel`
   and `systemctl restart dumbtunnel`. Restart, not start, so a new ticket takes
   effect on a relay that is already running.

Running it again with a new ticket moves the relay to that ticket. Running it twice
with the same ticket changes nothing.

### 7.1 The suite's stand-ins

The suite runs `install.sh` in a container, with stand-ins on `PATH`:

- `systemctl` and `netfilter-persistent` only record their arguments.
- `iptables` keeps the filter table's `INPUT` chain in a file. It understands `-C`,
  `-I [N]`, `-A`, `-D` and `-S`, with optional `-w` and `-t filter`. It does not
  understand `-L`. It compares rules as the literal text given, word for word, the
  way they were added. It starts with the rules of Oracle's Ubuntu images:

  ```text
  -m state --state RELATED,ESTABLISHED -j ACCEPT
  -p icmp -j ACCEPT
  -i lo -j ACCEPT
  -p udp -m udp --sport 123 -j ACCEPT
  -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
  -j REJECT --reject-with icmp-host-prohibited
  ```

  A rule accepts TCP port 443 when it has the words `-p tcp`, `--dport 443` and
  `-j ACCEPT`.

The suite reads `ExecStart=` by dropping systemd's prefix characters `-@:+!` and
splitting the rest as `sh` would, then runs it for real and expects TCP port 443 to
listen on all interfaces within 30 seconds.

## 8. Lifecycle

1. On the laptop, `dumbtunnel ticket` prints the ticket.
2. On the relay, `install.sh TICKET` installs dumbpipe and starts the service.
3. The domain and its subdomains point at the relay.
4. On the laptop, the user copies `Caddyfile.example` to `Caddyfile` and puts their
   own names in it.
5. `dumbtunnel` in that directory prints the ticket line and serves. Caddy gets a
   certificate for each name at start.
6. Ctrl-C stops dumbpipe and Caddy.
7. Later, `dumbtunnel` serves the same sites again. The secret is the same, so the
   relay still works.

## 9. Observable strings

| Where | Text |
| --- | --- |
| stdout, when serving | `ticket: TICKET` |
| stdout, ticket mode | `TICKET` |
| stderr, no file at the Caddyfile path | starts with `usage: dumbtunnel`, exit status 2 |
| stderr, dumbpipe exits before the ticket | what dumbpipe wrote, nonzero exit status |
| relay | the systemd unit `dumbtunnel.service` |

The reference's usage line is `usage: dumbtunnel [CADDYFILE] | dumbtunnel ticket`.

## 10. State and files

| Path | What it holds |
| --- | --- |
| `DIR/secret` | The secret, 64 lowercase hex characters. Mode `600` when dumbtunnel creates it. Never printed. |
| The Caddyfile | The user's, wherever they keep it. dumbtunnel passes it to Caddy and never writes it. |
| `Caddyfile.example` | In the repository. The user copies it. |
| Caddy's data directory | Certificates and the ACME account. Caddy's default, set by Caddy and `XDG_DATA_HOME`, not by dumbtunnel. |
| `/usr/local/bin/dumbpipe` | On the relay, from `install.sh`. |
| `/etc/systemd/system/dumbtunnel.service` | On the relay, from `install.sh TICKET`. |

dumbtunnel MAY make other files in the directory while it runs, such as a FIFO. They
MUST be gone when it exits.

## 11. What the tests leave out

- That Caddy starts only after the ticket line. Started earlier, Caddy's first
  challenge can fail, and Caddy retries a minute or more later.
- Issuance from Let's Encrypt itself. The end-to-end test uses Pebble, Let's
  Encrypt's test CA.
- The comments in `Caddyfile.example`.
- macOS. The suite runs on busybox. The scripts MUST still work under macOS
  `/bin/sh`, so try them there by hand.
- `install.sh` on a real VM, with real systemd and iptables.
- The order and content of stderr, beyond the usage line and dumbpipe's error.

## 12. Known limits

Keep these. They are trade-offs, not bugs to fix.

- If dumbpipe dies while Caddy runs, dumbtunnel keeps running with the tunnel down.
- dumbtunnel does not check the Caddyfile. One without the example's global options
  can open port 80, turn on HTTP/3, or use a challenge that cannot reach the laptop.
- dumbtunnel reads the ticket from the text dumbpipe `v0.39.0` prints. A dumbpipe
  that prints it differently and keeps running leaves dumbtunnel waiting.
- Caddy MAY listen on all interfaces, so machines on the same network can reach it
  at the port.
- One relay serves one laptop, the one in its ticket.
- The app sees every request come from `127.0.0.1`. The relay forwards plain TCP, so
  the client's address is lost.
- No HTTP/3, and nothing on port 80, so `http://` addresses do not redirect.
- `dumbtunnel ticket` while dumbtunnel runs starts a second copy of the same key,
  and the two fight over the connection.
- Oracle can reclaim an Always Free VM that stays idle for 7 days.

## 13. Non-goals

- Code on the relay beyond stock dumbpipe, and TLS on the relay.
- Authentication. Users add `basic_auth` to the Caddyfile themselves.
- Writing or checking Caddy configuration. Caddy's own docs cover the Caddyfile.
- Running dumbtunnel as a service on the laptop.
- Windows.
- Several laptops behind one relay, or routing by name on the relay.
- Managing DNS records, VMs or accounts.
