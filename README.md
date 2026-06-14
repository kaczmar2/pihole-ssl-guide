# Pi-hole v6 SSL Certificates

Create your own trusted SSL certificate for the
[Pi-hole v6](https://pi-hole.net/blog/2025/02/18/introducing-pi-hole-v6/#page-content) web
interface — automated with a single interactive script. Choose an internal Certificate
Authority (recommended) or a standalone self-signed certificate.

## Overview

Pi-hole v6 replaced `lighttpd` with an embedded web server. To serve HTTPS with your own
certificate, Pi-hole needs a single **PEM file containing both the certificate and its private
key** at `/etc/pihole/tls.pem`. The scripts in this repo generate that file with the hostnames
and IPs you specify, and can deploy it to Pi-hole for you.

> **Scope:** This guide targets a standard **bare-metal** Pi-hole install (installed directly on the host OS, not in a container) — the commands use the host's
> `/etc/pihole` directory and `sudo service pihole-FTL restart`. If Pi-hole runs in **Docker**
> (`docker-pi-hole`), generate the certificate the same way, then mount `tls.pem` to
> `/etc/pihole/tls.pem` in the container (or set the `FTLCONF_webserver_tls_cert` environment
> variable) and restart with `docker restart pihole`.

## Which method?

- **Method 1 — Internal CA (recommended).** Create a Certificate Authority once, import it into
  your browser once, and every certificate you sign with it is trusted automatically —
  including certificates for future servers. Best when you have more than one device or service
  to secure.
- **Method 2 — Self-signed.** Generate a single standalone certificate. Simpler, but you must
  import each certificate into every browser individually. Fine for a single Pi-hole.

## Quick Start (automated)

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

### 3. Run the script for your chosen method

```bash
# Method 1 — Internal CA (recommended)
./scripts/method1-ca-signed.sh

# Method 2 — Self-signed
./scripts/method2-self-signed.sh
```

The script is interactive: it prompts for your organization details, hostnames (DNS SANs), and
IP addresses, generates the certificate, and **optionally deploys** `tls.pem` to `/etc/pihole`
and restarts `pihole-FTL` for you. Run it **on the Pi-hole host** if you want it to deploy
automatically (it will use `sudo`); otherwise copy the resulting `tls.pem` to `/etc/pihole` on
the Pi-hole machine yourself and run `sudo service pihole-FTL restart`.

## What the scripts produce

Files are written to a working directory (`~/crt` by default).

**Method 1 (CA-signed):**

| File | Purpose |
|------|---------|
| `homelabCA.key` | CA private key — keep this secure |
| `homelabCA.crt` | CA certificate — import into browsers (one-time) |
| `cert.cnf` | OpenSSL config generated from your input |
| `tls.key` | Server private key |
| `tls.csr` | Certificate signing request |
| `tls.crt` | Signed server certificate |
| `tls.pem` | Combined cert+key for Pi-hole |

**Method 2 (self-signed):**

| File | Purpose |
|------|---------|
| `cert.cnf` | OpenSSL config generated from your input |
| `tls.key` | Private key |
| `tls.crt` | Self-signed certificate — import into browsers |
| `tls.pem` | Combined cert+key for Pi-hole |

## Import the certificate into your browser

This is the one step the scripts can't do for you — import the certificate into your client's
**Trusted Root Certificate Store**.

| Method | File to import | Import once? |
|--------|---------------|--------------|
| Method 1 (CA) | `homelabCA.crt` | Yes — all future certs signed by this CA are trusted |
| Method 2 (self-signed) | `tls.crt` | No — import each new certificate individually |

First copy the file from the Pi-hole host to your client machine, e.g.:

```bash
# Method 1
scp user@pihole-server:~/crt/homelabCA.crt ~/Downloads/
# Method 2
scp user@pihole-server:~/crt/tls.crt ~/Downloads/
```

**Chrome (Windows):**
1. Open `chrome://certificate-manager`
2. Click **Manage Imported Certificates**
3. Open the **Trusted Root Certification Authorities** tab
4. Click **Import**, select the certificate file, and confirm the store is **Trusted Root
   Certification Authorities**
5. Click **Finish**

**Chrome / Safari (macOS):**
1. Double-click the `.crt` file to open it in Keychain Access (added to the **login** keychain)
2. Double-click the certificate, expand **Trust**, and set **When using this certificate** to
   **Always Trust**
3. Close the dialog and enter your password to confirm

**Firefox (any OS):**
1. Open `about:preferences#privacy` → **Certificates** → **View Certificates**
2. On the **Authorities** tab, click **Import** and select the certificate
3. Check **Trust this CA to identify websites**, then **OK**

**Mobile (iOS / Android):** see the
[official Pi-hole TLS documentation](https://docs.pi-hole.net/api/tls/).

## Issuing additional certificates with your CA (Method 1)

Re-run `./scripts/method1-ca-signed.sh`. It detects your existing CA and offers to **reuse** it,
so you don't re-import anything into your browser — every certificate it signs is already
trusted. (Declining reuse requires typing `OVERWRITE` to confirm, because regenerating the CA
invalidates every certificate previously signed by it.)

## Security best practices

A self-signed certificate or an internal CA is fine for a homelab. For anything internet-facing,
prefer **[Let's Encrypt](https://letsencrypt.org/)** — publicly trusted and automatically
renewed, so browsers show no warnings and there's no manual trust step. The author's companion
guides cover that:
[Let's Encrypt for Pi-hole v6](https://gist.github.com/kaczmar2/17f02a0ddb59a7d336b20376695797c6)
and
[Pi-hole v6 + Docker + Let's Encrypt](https://gist.github.com/kaczmar2/027fd6f64f4e4e7ebbb0c75cb3409787).
Self-signed / internal CA still makes sense for air-gapped networks or quick testing.

## Prefer to do it by hand?

Every step the scripts automate is written out as manual `openssl` commands in
**[manual-openssl-steps.md](manual-openssl-steps.md)** — useful for understanding exactly what
happens or adapting the process.
