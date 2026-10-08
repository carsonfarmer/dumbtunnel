# dumbtunnel

dumbtunnel serves ports on your laptop at public HTTPS addresses. Traffic comes in
through a small server you run, such as a free cloud VM. That server only forwards
encrypted bytes. The certificates and their keys stay on your laptop, so the server
cannot read or change what passes through it.

```console
$ dumbtunnel api=3000 web=5173
https://api.you.duckdns.org -> localhost:3000
https://web.you.duckdns.org -> localhost:5173
ticket: endpointaa...
```

There is very little here of its own. [dumbpipe](https://github.com/n0-computer/dumbpipe)
moves the bytes over [iroh](https://github.com/n0-computer/iroh), and
[Caddy](https://caddyserver.com) handles TLS, certificates and routing. dumbtunnel is
a shell script that starts both, and `install.sh` sets up the server.

## How it works

```text
browser ──TLS──▶ relay :443 ──iroh──▶ dumbpipe ──▶ Caddy :8443 ──▶ localhost:3000
                 (free VM)                          (TLS ends)
                 └── sees only encrypted bytes ──┘  └──────── your laptop ────────┘
```

- **The relay** is a VM with a public IP address. It runs `dumbpipe connect-tcp`,
  which accepts TCP connections on port 443 and sends each one over iroh to your
  laptop. It does not hold a certificate and never decrypts anything.
- **Your laptop** runs `dumbpipe listen-tcp`, which hands each connection to Caddy.
  Caddy ends TLS and sends the request to a local port, chosen by hostname.
- **Certificates** come from Let's Encrypt. Caddy answers the TLS-ALPN-01 challenge,
  which arrives on port 443 through the relay like any other connection. You need no
  port 80 and no DNS API token.
- **iroh** connects the relay and the laptop. It finds the laptop by its public key,
  wherever it is, and gets through NAT. When it cannot connect directly, it routes
  through the public relay servers that n0 runs. Either way the connection is
  encrypted end to end.

The laptop's identity is a key that dumbtunnel creates on first use. The *ticket* is
the public half of that key plus the iroh relay server the laptop uses. The relay
needs the ticket to find the laptop.

## Setup

You need three things: a name, a relay, and the tools on your laptop.

### 1. The laptop

On macOS:

```bash
brew install caddy dumbpipe
```

Then put the `dumbtunnel` script somewhere on your `PATH`. On Linux, install Caddy
from your package manager, and `sudo sh install.sh` installs dumbpipe.

Print your ticket:

```bash
dumbtunnel ticket
```

### 2. The relay

Any Linux VM with systemd and a public IPv4 address works. The
[Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) includes two small VMs
and 10 TB of outbound traffic a month, for free. Google Cloud's free e2-micro also
works, but its free tier includes only 1 GB of outbound traffic a month.

On Oracle:

1. Create the network first. Under **Networking > Virtual cloud networks**, start
   the VCN wizard and choose **Create VCN with Internet Connectivity**. Then open
   its public subnet's default security list and add an ingress rule for TCP port
   443 from `0.0.0.0/0`.
2. Create a compute instance with an Ubuntu image and the `VM.Standard.E2.1.Micro`
   shape. If that shape is out of capacity, `VM.Standard.A1.Flex` is also free.
   Under networking, select the new network and its public subnet, and turn on
   **Automatically assign public IPv4 address**. Add your SSH key.
3. From your laptop, run `install.sh` on the VM with your ticket:

   ```bash
   ssh ubuntu@VM_IP 'sudo sh -s -- TICKET' < install.sh
   ```

`install.sh` downloads dumbpipe and adds a systemd service named `dumbtunnel` that
forwards port 443 to the ticket. On Oracle's Ubuntu images it also opens port 443 in
iptables. Run it again to change the ticket. Run `journalctl -u dumbtunnel -f` on
the VM to see its logs.

### 3. The name

Point a name and all its subdomains at the relay's IP address.
[DuckDNS](https://www.duckdns.org) does this for free: sign in, add a subdomain such
as `you`, and set its IP address. DuckDNS also answers for every name under yours,
so `api.you.duckdns.org` works with no more setup. With your own domain, add `A`
records for `example.com` and `*.example.com`.

### 4. Run it

```bash
export DUMBTUNNEL_DOMAIN=you.duckdns.org
dumbtunnel api=3000
```

The first request to a new name waits a few seconds while Caddy gets its
certificate.

## Usage

```text
dumbtunnel PORT                serve https://$DUMBTUNNEL_DOMAIN from localhost:PORT
dumbtunnel NAME=PORT...        serve https://NAME.$DUMBTUNNEL_DOMAIN from localhost:PORT
dumbtunnel NAME=HOST:PORT...   proxy to another address
dumbtunnel                     serve the same routes as last time
dumbtunnel ticket              print the ticket and exit
```

dumbtunnel also prints the ticket when it starts. Do not run `dumbtunnel ticket`
while dumbtunnel runs, because two copies of one key fight over its connection.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DUMBTUNNEL_DOMAIN` | none | The name that routes go under. Needed to set routes. |
| `DUMBTUNNEL_DIR` | `~/.config/dumbtunnel` | Where the key and the Caddyfile live. |
| `DUMBTUNNEL_ACME_CA` | Let's Encrypt | The ACME directory URL that Caddy gets certificates from. |
| `DUMBTUNNEL_PORT` | `8443` | The laptop port where Caddy listens and dumbpipe forwards. |

To try a setup without using up Let's Encrypt's rate limits, set
`DUMBTUNNEL_ACME_CA` to `https://acme-staging-v02.api.letsencrypt.org/directory`.
Browsers do not trust staging certificates.

To change more, such as adding `basic_auth`, edit `Caddyfile` in `DUMBTUNNEL_DIR`
and run `dumbtunnel` with no arguments. Setting new routes overwrites it.

## Reaching the laptop without the relay

Your other machines can skip the relay and connect over iroh, directly when they
can. The certificate is the same, so the name has to match:

```bash
dumbpipe connect-tcp --addr 127.0.0.1:8443 TICKET
curl --resolve api.you.duckdns.org:8443:127.0.0.1 https://api.you.duckdns.org:8443/
```

For a browser, add `127.0.0.1 api.you.duckdns.org` to `/etc/hosts` and open
`https://api.you.duckdns.org:8443`.

If you only want private access, you do not need dumbtunnel at all. Run
`dumbpipe listen-tcp --host localhost:3000` on the laptop and
`dumbpipe connect-tcp --addr 127.0.0.1:3000 TICKET` on the other machine.

## Security and privacy

- **The relay sees** client IP addresses, the hostnames in TLS handshakes, and the
  size and timing of traffic. It cannot read or change requests and responses.
- **Every route is public.** Anyone who knows the name can reach your local service.
  Protect it in the app or with `basic_auth` in the Caddyfile.
- **Names are public too.** Let's Encrypt logs every certificate it issues in public
  Certificate Transparency logs, so each name you serve is listed there.
- **Whoever controls the name or the relay** can get their own certificate for your
  names, and then could read traffic. That is you, so keep both accounts safe. The
  same logs would show such a certificate.
- **The key is a secret.** `secret` in `DUMBTUNNEL_DIR` is the laptop's private
  key, and whoever holds it can pose as your laptop. Do not share it or check it in.
- **The ticket is not a secret.** It holds only the public key and an iroh relay
  server. Anyone with it can reach Caddy on your laptop, the same as through the
  relay.

## Cost

Nothing, within the free tiers. The Oracle VM, DuckDNS and Let's Encrypt are free.
dumbpipe uses the relay servers and DNS that n0 runs for iroh, which are also free.
The relay has a public IP address, so iroh can usually connect it to your laptop
directly, and most traffic does not touch n0's relay servers.

## Limits

- One relay serves one laptop, the one in its ticket.
- Your app sees every request come from `127.0.0.1`. The relay forwards plain TCP,
  so Caddy never learns the client's real address.
- HTTP/1.1 and HTTP/2 only. HTTP/3 runs over UDP, and the relay forwards TCP.
- Nothing listens on port 80, so `http://` addresses do not redirect to `https://`.

## Testing

```bash
test/run.sh
```

runs an end-to-end test in Docker. A laptop container serves a page, a relay
container forwards to it, and [Pebble](https://github.com/letsencrypt/pebble), Let's
Encrypt's test CA, issues the certificate through the relay. A client then fetches
the page through the relay and again straight over iroh. The test needs the network,
because iroh finds the laptop through n0's servers. Set `RUST_LOG` to see more of
dumbpipe's logs.

## License

MIT. See [LICENSE](LICENSE).
