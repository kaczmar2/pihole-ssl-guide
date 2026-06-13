# Automation Scripts for Pi-hole v6 SSL Certificate Setup

This document describes the automation scripts in [`scripts/`](../scripts/) and covers the manual steps that cannot be automated.

## Scripts Overview

| Script | Method | What it automates |
|--------|--------|-------------------|
| `method1-ca-signed.sh` | Method 1: Internal CA | Steps 1–9 (CA creation, cert signing, deployment) |
| `method2-self-signed.sh` | Method 2: Self-Signed | Steps 1–7 (cert generation, deployment) |

Both scripts are interactive — they prompt you for certificate details (hostnames, IPs, organization info) and generate all files automatically.

## Prerequisites

- **Linux** (Debian/Ubuntu, RHEL/CentOS, or Fedora)
- **openssl** installed (the scripts check for this and exit with install instructions if missing)
- **sudo** access (only required if deploying to Pi-hole)

## Usage

### Method 1: CA-Signed Certificate (Recommended)

```bash
chmod +x scripts/method1-ca-signed.sh
./scripts/method1-ca-signed.sh
```

The script will:
1. Prompt for CA details (country, org, common name, validity)
2. Prompt for server certificate details
3. Prompt for DNS and IP SANs (Subject Alternative Names)
4. Create a working directory (`~/crt` by default)
5. Generate the CA key and certificate (`homelabCA.key`, `homelabCA.crt`)
6. Generate `cert.cnf` from your inputs
7. Generate a server key and CSR (`tls.key`, `tls.csr`)
8. Sign the CSR with your CA (`tls.crt`)
9. Create the combined `tls.pem` (cert + key)
10. **Optionally** deploy `tls.pem` to `/etc/pihole` and restart Pi-hole

**Files produced in `~/crt`:**

| File | Purpose |
|------|---------|
| `homelabCA.key` | CA private key — keep this secure |
| `homelabCA.crt` | CA certificate — import into browsers (one-time) |
| `cert.cnf` | OpenSSL configuration used for the certificate |
| `tls.key` | Server private key |
| `tls.csr` | Certificate Signing Request |
| `tls.crt` | Signed server certificate |
| `tls.pem` | Combined cert+key for Pi-hole |

### Method 2: Self-Signed Certificate

```bash
chmod +x scripts/method2-self-signed.sh
./scripts/method2-self-signed.sh
```

The script will:
1. Prompt for certificate details (country, org, common name, validity)
2. Prompt for DNS and IP SANs
3. Create a working directory (`~/crt` by default)
4. Generate `cert.cnf` from your inputs
5. Generate a self-signed key and certificate (`tls.key`, `tls.crt`)
6. Create the combined `tls.pem` (cert + key)
7. **Optionally** deploy `tls.pem` to `/etc/pihole` and restart Pi-hole

**Files produced in `~/crt`:**

| File | Purpose |
|------|---------|
| `cert.cnf` | OpenSSL configuration used for the certificate |
| `tls.key` | Private key |
| `tls.crt` | Self-signed certificate — import into browsers |
| `tls.pem` | Combined cert+key for Pi-hole |

---

## Manual Steps: Importing Certificates into Your Browser

The scripts handle everything on the Pi-hole server, but importing the certificate into your **client browser** must be done manually. This is the only step not automated.

### What to import

| Method | File to import | Import once? |
|--------|---------------|--------------|
| Method 1 (CA) | `homelabCA.crt` | Yes — all future certs signed by this CA are trusted |
| Method 2 (Self-Signed) | `tls.crt` | No — must import each new certificate individually |

### Step 1: Copy the certificate to your client machine

Transfer the appropriate file from your Pi-hole server to your local PC. For example, using `scp`:

```bash
# Method 1: Copy the CA certificate
scp user@pihole-server:~/crt/homelabCA.crt ~/Downloads/

# Method 2: Copy the self-signed certificate
scp user@pihole-server:~/crt/tls.crt ~/Downloads/
```

### Step 2: Import into Chrome (Windows)

1. Open Chrome and navigate to `chrome://certificate-manager`
2. Click **Manage Imported Certificates**
3. Click the **Trusted Root Certification Authorities** tab
4. Click **Import**
5. Click **Next**, browse to the certificate file, and click **Next**
6. Ensure the store is set to **Trusted Root Certification Authorities**
7. Click **Finish**

### Step 2 (Alternative): Import into Chrome (macOS)

1. Double-click the `.crt` file to open it in Keychain Access
2. It will be added to the **login** keychain
3. Find the certificate, double-click it
4. Expand **Trust** and set **When using this certificate** to **Always Trust**
5. Close the dialog and enter your password to confirm

### Step 2 (Alternative): Import into Firefox (Any OS)

1. Open Firefox and navigate to `about:preferences#privacy`
2. Scroll down to **Certificates** and click **View Certificates**
3. Go to the **Authorities** tab
4. Click **Import** and select the certificate file
5. Check **Trust this CA to identify websites**
6. Click **OK**

### Step 2 (Alternative): Import on Mobile Devices

See the [official Pi-hole TLS documentation](https://docs.pi-hole.net/api/tls/) for instructions on mobile devices (iOS, Android).

---

## Issuing Additional Certificates with Method 1

If you used Method 1 and want to create certificates for additional servers, you do **not** need to re-run the full script or re-import the CA into your browser.

Simply run the script again — it will detect the existing CA files and offer to reuse them, or you can manually run:

```bash
cd ~/crt

# Create a new cert.cnf for the other server (edit DNS/IP entries)
# Then generate and sign:
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout tls2.key -out tls2.csr -config cert2.cnf

openssl x509 -req -in tls2.csr -CA homelabCA.crt -CAkey homelabCA.key \
    -CAcreateserial -out tls2.crt -days 365 -sha256 \
    -extfile cert2.cnf -extensions v3_ext

cat tls2.crt tls2.key > tls2.pem
```

Since the browser already trusts your CA (`homelabCA.crt`), any certificate signed by it will be trusted automatically.
