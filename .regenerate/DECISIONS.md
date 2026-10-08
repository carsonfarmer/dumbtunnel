# Design decisions

A rebuild reads this file for the choices `SPEC.md` leaves open. Each entry gives the
decision and the reason for it.

- **Recorded** means the reason is written down in a README, a code comment, a commit
  message, or the log of the build session, which is kept only locally.
- **Inferred** means the reason was worked out from the code afterwards. Check these
  before you rely on them.

## Goal

D1. **Build the smallest thing that does the job.** dumbtunnel is glue. dumbpipe and
Caddy do the work, and the scripts start them and pass one string between them. The
budget is 40 lines of code for each script. `dumbtunnel` had 60 until D22 brought it
to 24, and the budget came down with it. Recorded (build session; README intro).

D2. **Come as close to opentunnel.xyz as a free setup can.** A public HTTPS name for a
local port, with the TLS key on the laptop and a relay that cannot read the traffic.
Recorded (build session, where it was named as the reference).

D3. **Serve both the public and the user's own machines.** Browsers reach the sites
through the relay. The user's other machines can skip the relay and dial the laptop
over iroh with the same ticket. Recorded (build session, design interview; README,
"Reaching the laptop without the relay").

D4. **Write POSIX shell.** The work is starting two programs and reading one line of
output. Shell does that with no build step, on macOS and on any Linux VM. Inferred.

## Transport

D5. **Use stock dumbpipe at both ends.** iroh finds the laptop by its key wherever it
is, gets through NAT, and encrypts the link, and the laptop opens no inbound port.
dumbpipe already exposes that as TCP forwarding, so there is no code of our own on the
wire. The question of dropping it came up after the build, and it stayed. Recorded
(build session, design interview and later).

D6. **Give the relay the short ticket.** The long ticket lists the laptop's IP
addresses, which go stale when it moves. An ID-only ticket makes the relay look the
laptop up in iroh's DNS. If that lookup runs before the laptop first publishes, the
resolvers cache the miss and the relay's dials fail for minutes. The short ticket
carries the laptop's home relay URL, so the first dial needs no DNS. After that, iroh
finds the laptop by its ID even if its home relay changes. Recorded (build session;
comment in `dumbtunnel`).

D7. **The relay keeps no key.** `dumbpipe connect-tcp` makes a new one each time it
starts. The relay holds no secret worth stealing and no state. Inferred.

## The relay host

D8. **Use a VM, not a container host.** Free container hosts accept HTTP through
their own proxy, which ends TLS, so the relay could not be blind. A VM with a public
IPv4 address takes raw TCP on port 443. Recorded (build session, design interview).

D9. **Suggest Oracle Cloud's Always Free tier.** It includes 10 TB of outbound
traffic a month. Google Cloud's free e2-micro includes 1 GB. Recorded (README,
"Setup").

D10. **One relay serves one laptop.** Routing several laptops by name would need code
on the relay or a second program there. Recorded (`SPEC.md`, sections 12 and 13).
The reason is inferred.

D11. **Create the Oracle network before the instance.** The instance form's own
network option leaves the public IPv4 toggle greyed out, so the VM gets no public
address. Recorded (commit `521662d`).

D12. **Open port 443 in iptables only on Oracle's images.** They ship rules that
reject inbound traffic, on top of the network's security list. `netfilter-persistent`
marks those images, so `install.sh` touches iptables only when it is present. Recorded
(build session; comment in `install.sh`).

D13. **Run the relay as a systemd service without root.** `DynamicUser=yes` with
`CAP_NET_BIND_SERVICE` binds port 443 and nothing more. `Restart=always` brings it
back after a crash or a reboot. Inferred.

D14. **Install the official dumbpipe release.** The release archive holds a static
binary that runs on any distro, so a small VM never builds Rust. `install.sh` runs
over ssh from the laptop, so nothing is copied to the VM first. Without a ticket it
only installs dumbpipe, which serves Linux laptops and the test image. Recorded (build
session; comment in `install.sh`).

## Names and certificates

D15. **End TLS on the laptop.** The certificate's key never leaves it, so the relay
sees only encrypted bytes. This is the point of the project. Recorded (README intro).

D16. **Use Caddy.** With TLS ending on the laptop and the challenge arriving on port
443 (D17), the server on that port needs its certificate client built in. Caddy has
that, and also routes by name, speaks HTTP/2 and WebSockets, renews certificates and is
one `brew install`. The others were turned down: Traefik needs more configuration,
Homebrew's nginx lacks the ACME module, HAProxy's ACME support documents only HTTP-01,
certbot has no TLS-ALPN-01, lego and acme.sh are a second tool with scheduled
renewals, and Go's autocert is custom code. The cost is a 46 MB binary. Recorded
(build session).

D17. **Use the TLS-ALPN-01 challenge only.** The relay carries port 443 and nothing
else, so HTTP-01 cannot reach the laptop. A DNS challenge needs an API token for the
DNS provider. TLS-ALPN-01 arrives on port 443 like any other connection. Recorded
(README, "How it works").

D18. **Use one issuer, Let's Encrypt.** Caddy's default adds ZeroSSL as a second
issuer. With one, the setup behaves the same every time, and one variable swaps the
CA for staging or for the tests. The build session records the choice. The reason is
inferred.

D19. **Get a certificate per name, not a wildcard.** A wildcard needs the DNS
challenge, and so a DNS token on the laptop. As a result, every name appears in
public Certificate Transparency logs. Recorded (build session; README, "Security and
privacy").

D20. **Suggest DuckDNS.** It is free, and every name under a DuckDNS subdomain
resolves to the same address. It is on the Public Suffix List, so Let's Encrypt's
limit of 50 certificates a week applies to each user's subdomain. sslip.io and
nip.io are not on the list, so all their users share one limit. Recorded (build
session; README, "Setup").

D21. **Try a setup on Let's Encrypt staging first.** A setup that fails while it is
being built uses up production rate limits. `DUMBTUNNEL_ACME_CA` switches to staging.
Recorded (README, "Usage").

## Caddy configuration

D22. **The Caddyfile belongs to the user.** The user copies `Caddyfile.example` and
edits it. dumbtunnel passes it to Caddy and never writes or checks it. An earlier
version built a Caddyfile from `NAME=PORT` arguments and a domain variable. A plain
Caddyfile is less code, shows exactly what runs, and accepts anything in Caddy's docs.
dumbtunnel becomes `caddy run`, reachable from the internet. Recorded (commit
`3cd5b23`; build session).

D23. **Keep the settings every user needs in the example's global block.** A comment
says to keep it. Recorded (comments in `Caddyfile.example`).

D24. **Nothing on port 80, and no redirects.** The relay carries only port 443, so a
redirect server would never be reached. Recorded (comment in `Caddyfile.example`).

D25. **HTTP/1.1 and HTTP/2 only.** HTTP/3 runs over UDP, which the relay does not
carry. Caddy would advertise it, and browsers would try it. Recorded (README,
"Limits").

D26. **Turn off the admin endpoint.** Then the port is the only thing Caddy listens
on, two runs do not compete for the admin port, and no local process can change the
running config. Inferred.

D27. **Forward to `127.0.0.1:8443` by default.** Port 443 on the laptop would need
root. `DUMBTUNNEL_PORT` changes it, and both dumbtunnel and the example read it.
Inferred.

D28. **Read the CA and the port when Caddy starts.** The example uses Caddy's
`{$VAR:default}` placeholders, so changing either needs no edit. Recorded (build
session; `Caddyfile.example`).

## The process

D29. **Run in the foreground until Ctrl-C.** The tunnel is up while the command runs.
There is no service on the laptop. Recorded (`SPEC.md`, section 13). The reason is
inferred.

D30. **Start Caddy only after dumbpipe is online.** Started earlier, Caddy's first
challenge can reach the relay before the laptop does, and Caddy retries a minute or
more later. Recorded (comment in `dumbtunnel`).

D31. **Read the ticket through a FIFO in the key directory.** dumbpipe prints the
short ticket only on stderr, among its logs. The FIFO lives next to the key, so the
current directory, which may be a project's, stays untouched. It is removed on every
exit, even when dumbpipe has already gone. Recorded (commit `b39d676`; build
session).

D32. **Stop Caddy on SIGHUP.** Caddy ignores SIGHUP, so closing the terminal left it
running. It binds with `SO_REUSEPORT`, so the next run shared the port with the stale
copy. Caddy now runs in the background and the script waits for it, so the traps stop
both programs. Recorded (commit `09db2ab`).

D33. **stdout carries only the ticket.** Scripts can capture it, as in
`ticket=$(dumbtunnel ticket)`. A log line that once reached stdout broke the
end-to-end test. Everything else goes to stderr. Recorded (build session).

D34. **Fail when dumbpipe exits before the ticket.** Otherwise `dumbtunnel ticket`
printed an empty line and exited 0, and `dumbtunnel` started Caddy with no tunnel.
Recorded (commit `8673030`).

D35. **Do not watch dumbpipe once Caddy runs.** If dumbpipe dies, the tunnel is down
and dumbtunnel keeps running. Watching both needs bash's `wait -n` or a polling loop.
Recorded (build session; `SPEC.md`, section 12).

D36. **Keep the secret in a file, created on first use.** The ticket then survives
restarts, and the relay keeps working. The secret goes to dumbpipe only through
`IROH_SECRET`, because without it dumbpipe makes a new key and prints it. Recorded
(README, "Security and privacy").

D37. **Print the ticket on its own with `dumbtunnel ticket`.** The relay needs the
ticket before the first real run. Recorded (README, "Setup").

## Tests

D38. **Run every test in Docker, with Pebble as the CA.** A test never contacts a real
CA, never reads the real key, and never touches Caddy's data on the host. A test run on
the host once overwrote Caddy's saved config. Recorded (commit `8c65e6e`; build
session).

D39. **Judge the scripts from outside.** The suite runs them by name on busybox, with
stand-ins for `systemctl`, `netfilter-persistent`, `iptables` and the CA. It looks
only at what a user could see, so it can judge a rebuild. Recorded (commit `8c65e6e`).

## Setup and upkeep

D40. **The person makes the accounts and the agent guides.** The setup needs a cloud
account, a DNS name and an SSH key. The person signs up, signs in and pays, if
anything. The agent explains each step and checks the result with `ssh`, `dig` and
`curl`. It never asks for a password or a card. Recorded (build session).

D41. **Fix upstream bugs upstream.** A workaround stays here only until the fix is
released. Recorded (`AGENTS.md`).
