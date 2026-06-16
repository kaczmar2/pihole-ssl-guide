# Pi-hole v6 SSL — Self-signed (alternative method)

> The recommended approach for everyone is the **internal CA** method — see the
> **[README](README.md)**. It's superior even for a single Pi-hole, especially with the
> automation. Self-signed is documented here as an alternative; its trade-off is that **every
> certificate must be trusted individually on each device** (there's no shared CA to trust
> once).

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
./scripts/self-signed.sh
```

The script prompts for your organization details, hostnames (DNS SANs), and IP addresses, then
generates a self-signed certificate and `tls.pem`, and optionally deploys it.

## Deploy the certificate

Deployment is identical to the CA method — see
**[Deploy the certificate](README.md#deploy-the-certificate)** in the README (the script's
host/docker prompt, or the manual recipes).

## Import the certificate into your browser

Follow the same steps as the CA import —
**[Import the certificate into your browser](README.md#import-the-certificate-into-your-browser)**
in the README — with two differences:

- Import **`tls.crt`** (the self-signed certificate), not `homelabCA.crt`.
- You must **repeat the import for every certificate** you generate — there's no shared CA to
  trust once.

## Prefer to do it by hand?

Every step the script automates is written out as manual `openssl` commands in
**[manual-openssl-self-signed.md](manual-openssl-self-signed.md)**.
