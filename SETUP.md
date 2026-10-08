# Setting up dumbtunnel with an agent

This file is for a coding agent. A person has given you this repository and wants
help to set up dumbtunnel: a site on their laptop, served at a public HTTPS name,
through a relay they run. Read [README.md](README.md) and this file in full, then
work through the steps below with them.

## Who does what

- **The person** creates accounts, signs in, types passwords, card numbers and
  one-time codes, agrees to terms, and clicks through the cloud console.
- **You** explain each step before it starts, run the commands on the laptop, and
  check every result yourself with `ssh`, `dig`, `curl` and `nc`. Do not take the
  person's word that a step worked when a command can tell you.
- **Never ask for, read or print** a password, a card number, a one-time code, an
  API token, the DuckDNS token, or the `secret` file in `~/.config/dumbtunnel`. None
  of the steps needs them. If the person pastes one, do not use it, and tell them to
  change it.
- **Ask first** before you install software, write outside the repository, or delete
  anything.
- Keep a short list of the steps that are done, so that you can pick up where you
  left off.

## 1. Interview

Ask these one at a time, and recommend an answer when the person is unsure:

1. **The laptop.** macOS or Linux? Windows is not supported.
2. **What to serve.** An app on a local port, such as a dev server on 3000? A folder
   of files? Anything Caddy can serve works.
3. **The name.** Do they have a domain with DNS they can edit? If not, recommend a
   free [DuckDNS](https://www.duckdns.org) name.
4. **The relay.** Do they have a Linux VM with systemd and a public IPv4 address? If
   not, recommend the [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/).
5. **The build.** Use the scripts in this repository, or build them fresh from the
   spec? See step 2.

Before you go on, tell them what they are signing up for:

- Every site is public. Anyone who knows the name can reach it.
- Each name appears in public Certificate Transparency logs.
- Within the free tiers, the setup costs nothing. Oracle's sign-up asks for a card
  to verify the account.

Then sum up the plan in a few lines and get a yes.

## 2. Build

The repository holds a working build: `dumbtunnel`, `install.sh` and
`Caddyfile.example`. CI checks them against the spec on every push.

If the person wants their own build, follow the blind mode in
[`.regenerate/README.md`](.regenerate/README.md). Start a separate agent in an empty
workspace that holds only the spec, the decisions, the prompt and the license, and
keep it away from this checkout. Then run the spec suite on what it wrote. Use the
new build only if every step passes. Otherwise use the scripts here, and record the
failure in the ledger in [`.regenerate/PROVENANCE.md`](.regenerate/PROVENANCE.md).

The spec suite needs Docker and the network. If Docker is there, run it on whichever
scripts the person will use:

```bash
.regenerate/check.sh
```

## 3. The laptop

On macOS:

```bash
brew install caddy dumbpipe
brew list --versions dumbpipe
```

dumbtunnel reads the ticket from the text that one dumbpipe release prints, the one
in section 2 of [`.regenerate/SPEC.md`](.regenerate/SPEC.md). If Homebrew has a
different release, `sudo sh install.sh` installs that one in `/usr/local/bin`, which
must exist first. Then `/usr/local/bin` has to come before Homebrew's directory on
`PATH`.

On Linux, install Caddy from [its install page](https://caddyserver.com/docs/install)
and dumbpipe with `sudo sh install.sh`.

Copy `dumbtunnel` to a directory on the person's `PATH`, such as `~/.local/bin`,
with `install -m 755 dumbtunnel ~/.local/bin/`. Then print the ticket:

```bash
dumbtunnel ticket
```

The first run creates the laptop's key. The ticket is one line that starts with
`endpoint`. It is not a secret. Never run `dumbtunnel ticket` while dumbtunnel
runs, because the two copies of the key fight over the connection.

## 4. The relay

These steps are for Oracle. On another VM, open TCP port 443 in its firewall, and go
to the `install.sh` step with its user name and address.

1. **Account.** The person signs up for the Free Tier and signs in to the console.
   The home region cannot be changed later, so suggest one near the laptop.
2. **SSH key.** Make a key for this relay only. A passphrase needs the person to
   type it, so either they run `ssh-keygen` themselves, or, with their OK, you run:

   ```bash
   ssh-keygen -t ed25519 -N '' -C dumbtunnel -f ~/.ssh/dumbtunnel
   cat ~/.ssh/dumbtunnel.pub
   ```

   The `.pub` file is the public half, and the person pastes it into the console.
3. **Network, before the instance.** Under **Networking > Virtual cloud networks**,
   the person starts the VCN wizard and chooses **Create VCN with Internet
   Connectivity**. Then they open the public subnet's default security list and add
   an ingress rule for TCP port 443 from `0.0.0.0/0`. If the instance comes first,
   the public IPv4 option is greyed out.
4. **Instance.** Under **Compute > Instances**, the person creates an instance with
   an Ubuntu image and the `VM.Standard.E2.1.Micro` shape. If that shape has no
   capacity, `VM.Standard.A1.Flex` is also free. Under networking they pick the new
   network and its public subnet and turn on **Automatically assign public IPv4
   address**. Under SSH keys they paste the public key. When it runs, they give you
   its public IP address.
5. **install.sh.** Check the login, then install the relay with the ticket:

   ```bash
   ssh -i ~/.ssh/dumbtunnel -o StrictHostKeyChecking=accept-new ubuntu@VM_IP true
   ssh -i ~/.ssh/dumbtunnel ubuntu@VM_IP 'sudo sh -s -- TICKET' < install.sh
   ```

6. **Check it.** The service is active, and port 443 answers from the laptop:

   ```bash
   ssh -i ~/.ssh/dumbtunnel ubuntu@VM_IP 'systemctl is-active dumbtunnel'
   nc -vz -w 5 VM_IP 443
   ```

   If `nc` fails, check the ingress rule first. Then read the service's log with
   `journalctl -u dumbtunnel -n 50 --no-pager` on the VM.

Tell the person that Oracle can reclaim an Always Free VM that stays idle for 7
days. Oracle's documentation says how to avoid that.

## 5. The name

With DuckDNS, the person signs in, adds a subdomain such as `you`, sets its IP
address to the relay's, and saves. Every name under it, such as
`api.you.duckdns.org`, then points at the relay too. You do not need the DuckDNS
token.

With their own domain, they add `A` records for `example.com` and `*.example.com`
that point at the relay.

Check both the name and a name under it. Each should print the relay's address:

```bash
dig +short you.duckdns.org @1.1.1.1
dig +short api.you.duckdns.org @1.1.1.1
```

## 6. The Caddyfile

Agree on a directory for it with the person, such as `~/dumbtunnel`. Copy the
example there:

```bash
mkdir -p ~/dumbtunnel
cp Caddyfile.example ~/dumbtunnel/Caddyfile
```

In the copy, change `api.you.duckdns.org` to a name under theirs, and
`localhost:3000` to their app's port. For a folder of files, use the commented
`file_server` example instead. Keep the block at the top. It is what makes Caddy
work through the relay. Then check the file, and check that the app answers:

```bash
caddy adapt --config ~/dumbtunnel/Caddyfile --adapter caddyfile >/dev/null
curl -sS localhost:3000
```

## 7. Try it on Let's Encrypt staging

A setup that fails on the way uses up Let's Encrypt's rate limits, so the first run
uses staging. dumbtunnel runs in the foreground until Ctrl-C. Run it where the
person can see it and stop it:

```bash
cd ~/dumbtunnel
DUMBTUNNEL_ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory dumbtunnel
```

It prints `ticket: …`, and Caddy logs `certificate obtained successfully` for each
name within a minute. Browsers do not trust staging certificates, so check with
`-k`:

```bash
curl -sSk https://api.you.duckdns.org/
```

The page should be the app's. Then stop dumbtunnel with Ctrl-C.

## 8. Run it for real

```bash
cd ~/dumbtunnel
dumbtunnel
```

Check it without `-k` this time, then have the person open the address in a browser:

```bash
curl -sS https://api.you.duckdns.org/
```

## 9. When something fails

| What you see | Check | Likely cause |
| --- | --- | --- |
| No `ticket:` line | `brew list --versions dumbpipe` against `SPEC.md`, and the network | A different dumbpipe release, or no route to n0's servers. |
| `nc` to port 443 fails | The ingress rule, then `systemctl status dumbtunnel` on the VM | The security list, or the service is down. |
| Port 443 answers, but `curl` hangs or fails TLS | `systemctl cat dumbtunnel` on the VM against `dumbtunnel ticket`, run while dumbtunnel is stopped | dumbtunnel is not running, or the relay has another ticket. Run `install.sh` again with the right one. |
| Caddy logs challenge errors | `dig`, and the top block against `Caddyfile.example` | The name does not point at the relay, the top block changed, or a rate limit. |
| `502` from Caddy | `curl localhost:PORT` | The app is not running on that port. |
| `http://` does not work | | Expected. Nothing listens on port 80. Use `https://`. |

dumbtunnel's stderr holds Caddy's and dumbpipe's logs. Never show a line that
contains `secret key`.

## 10. Hand it over

Tell the person:

- How to start it, `cd ~/dumbtunnel && dumbtunnel`, and stop it, Ctrl-C. The ticket
  stays the same, so the relay keeps working across restarts.
- More sites go in the Caddyfile, as more blocks with names under theirs. Restart
  dumbtunnel to pick them up.
- Every site is public. To limit one to people with a password, add `basic_auth`
  to its block. `caddy hash-password` makes the hash, and the person types the
  password themselves.
- `~/.config/dumbtunnel/secret` is the laptop's key. Keep it, and do not share it.
- Their other machines can skip the relay, as the README's section "Reaching the
  laptop without the relay" shows.

## 11. Tear it down

Only when the person asks:

1. Stop dumbtunnel.
2. The person terminates the instance, and the network if they want, in Oracle's
   console.
3. The person deletes the DuckDNS subdomain or the DNS records.
4. With their OK, remove `~/.ssh/dumbtunnel` and `~/.ssh/dumbtunnel.pub`, the copied
   `dumbtunnel` script, and `~/dumbtunnel`. Removing `~/.config/dumbtunnel` deletes
   the key, and the old ticket stops working for good.
