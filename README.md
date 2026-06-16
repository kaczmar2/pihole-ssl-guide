# Pi-hole v6 SSL Certificates

Create your own browser-trusted SSL certificate for the
[Pi-hole v6](https://pi-hole.net/blog/2025/02/18/introducing-pi-hole-v6/#page-content) web
interface — automated with a single interactive script. This guide uses an **internal
Certificate Authority (CA)**: you trust the CA in your browser once, and every certificate it
signs is trusted automatically.

## Overview

Pi-hole v6 replaced `lighttpd` with an embedded web server. To serve HTTPS with your own
certificate, Pi-hole needs a single **PEM file containing both the certificate and its private
key** at `/etc/pihole/tls.pem`. The script generates that file with the hostnames and IPs you
specify, and can deploy it to Pi-hole for you.

> **Scope:** This works for Pi-hole v6 whether it's installed **bare-metal** (directly on the
> host OS) or running in **Docker** (`docker-pi-hole`). The certificate is generated the same
> way for both, and the script can deploy to either — see
> [Deploy the certificate](#deploy-the-certificate).

## Why an internal CA?

With an internal CA you import **one** certificate (the CA) into your browser a single time;
after that, every certificate the CA signs is trusted automatically — including certificates
for other servers and services you add later.

> Self-signed certificates also work ([Self-signed guide](self-signed.md)), but every
> certificate must be trusted individually on each device. The internal CA method avoids that —
> it's recommended even for a single Pi-hole, especially with this script automating it.

## Quick Start

### 1. Install openssl

```bash
sudo apt update && sudo apt install openssl -y   # Debian/Ubuntu
sudo dnf install openssl -y                       # Fedora
sudo yum install openssl -y                       # RHEL/CentOS
```

### 2. Download this repo

```bash
mkdir -p ~/pihole-ssl && cd ~/pihole-ssl
curl -L -o main.tar.gz https://github.com/kaczmar2/pihole-ssl-guide/archive/refs/heads/main.tar.gz
tar -xzf main.tar.gz --strip-components=1
```

### 3. Run the script

```bash
./scripts/ca-signed.sh
```

> The scripts ship executable, so this should just work. If you get a `Permission denied`,
> make them executable first: `chmod +x scripts/*.sh`.

The script prompts for your organization details, hostnames (DNS SANs), and IP addresses, then
creates the CA and signs the certificate. At the end it **optionally deploys** the certificate
for you (see [Deploy the certificate](#deploy-the-certificate)) — or you can skip and deploy it
yourself.

## Deploy the certificate

Pi-hole loads its certificate from a single PEM file at `/etc/pihole/tls.pem`. On a **bare-metal**
Pi-hole the script runs on the Pi-hole machine itself. For **Docker**, run the script on the
**Docker host** (where the `docker` command lives) — not inside the container.

### Automated (recommended)

At the end of the run the script asks `Deploy the certificate now? [y/N]`. Answer **y**, then
choose **[h]ost** (bare-metal) or **[d]ocker**. The host path copies `tls.pem` into
`/etc/pihole` and restarts `pihole-FTL`; the Docker path lists your running containers, copies
`tls.pem` into the one you pick, and restarts it.

### Manual — bare-metal

```bash
sudo cp tls.pem /etc/pihole/tls.pem
sudo service pihole-FTL restart
```

### Manual — Docker

Run these on the **Docker host** (default container name `pihole`):

```bash
docker cp tls.pem pihole:/etc/pihole/tls.pem
docker restart pihole
```

If your `docker-compose` bind-mounts `/etc/pihole` to a host directory (e.g.
`/srv/docker/pihole/etc-pihole`), you can instead drop `tls.pem` straight into that directory
and restart the container.

## Import the certificate into your browser

This is the one step the script can't do for you: import the **CA certificate**
(`homelabCA.crt`) into your client's **Trusted Root Certificate Store**. You do this **once** —
every certificate the CA signs is then trusted.

### Step 1: Copy `homelabCA.crt` to your computer

On **Windows**, open a **PowerShell** window (it opens in your home directory) and run, swapping
in your Pi-hole's username and hostname:

```powershell
scp user@pihole:~/crt/homelabCA.crt ~/Downloads/
```

On macOS/Linux, run the same `scp` command from a terminal.

### Step 2: Import it

**Windows (Chrome / Edge):**
1. Open `chrome://certificate-manager`
2. Click **Manage imported certificates**, then open the **Trusted Root Certification
   Authorities** tab
3. Click **Import** and select `homelabCA.crt`
4. The Certificate Import Wizard opens with **"Place all certificates in the following store"**
   already selected and **"Trusted Root Certification Authorities"** pre-filled — leave both as
   they are, then **Next** → **Finish**
5. Confirm the security warning with **Yes** — you should see **"The import was successful."**

**macOS (Chrome / Safari):**
1. Double-click `homelabCA.crt` to open it in Keychain Access (added to the **login** keychain)
2. Double-click the certificate, expand **Trust**, and set **When using this certificate** to
   **Always Trust**
3. Close the dialog and enter your password to confirm

**Firefox (any OS):**
1. Open `about:preferences#privacy` → **Certificates** → **View Certificates**
2. On the **Authorities** tab, click **Import** and select `homelabCA.crt`
3. Check **Trust this CA to identify websites**, then **OK**

**Mobile (iOS / Android):** see the
[official Pi-hole TLS documentation](https://docs.pi-hole.net/api/tls/).

## Issuing additional certificates

Re-run `./scripts/ca-signed.sh`. It detects your existing CA and offers to **reuse** it, so you
don't re-import anything into your browser — every certificate it signs is already trusted.
(Declining reuse requires typing `OVERWRITE` to confirm, because regenerating the CA invalidates
every certificate previously signed by it.)

## Verify it worked

Browse to your Pi-hole admin page over HTTPS (e.g. `https://pi.hole/admin`, or your hostname).
You should see the padlock with no certificate warning.

> **Tip:** you may need to fully **close and reopen** your browser before it picks up the newly
> trusted CA.

## What the script does & produces

`scripts/ca-signed.sh` creates a Certificate Authority, generates a server key and CSR, signs
the certificate with the CA, and combines the certificate and key into `tls.pem` — then
optionally deploys it. Files are written to a working directory (`~/crt` by default):

| File | Purpose |
|------|---------|
| `homelabCA.key` | CA private key — keep this secure |
| `homelabCA.crt` | CA certificate — import into browsers (one-time) |
| `cert.cnf` | OpenSSL config generated from your input |
| `tls.key` | Server private key |
| `tls.csr` | Certificate signing request |
| `tls.crt` | Signed server certificate |
| `tls.pem` | Combined cert+key for Pi-hole |

## Security best practices

An internal CA is great for a homelab. For anything internet-facing, prefer
**[Let's Encrypt](https://letsencrypt.org/)** — publicly trusted and automatically renewed, so
browsers show no warnings and there's no manual trust step. The author's companion guides cover
that: [Let's Encrypt for Pi-hole v6](https://gist.github.com/kaczmar2/17f02a0ddb59a7d336b20376695797c6)
and [Pi-hole v6 + Docker + Let's Encrypt](https://gist.github.com/kaczmar2/027fd6f64f4e4e7ebbb0c75cb3409787).
An internal CA still makes sense for air-gapped networks or quick testing.

## Prefer to do it by hand?

Every step the script automates is written out as manual `openssl` commands in
**[manual-openssl-ca.md](manual-openssl-ca.md)** — useful for understanding exactly what happens
or adapting the process.
