# Pi-hole v6 SSL — Self-signed, Manual (openssl) Steps

> **Most people should use the internal CA method** ([README](README.md)). If you specifically
> want self-signed, the automated path is **[self-signed.md](self-signed.md)**; this is the
> by-hand `openssl` procedure that `scripts/self-signed.sh` automates.

## Prerequisites

Install `openssl` (see the [README Quick Start](README.md#1-install-openssl)). This guide
assumes all commands run from your home directory, and that `tls.pem` ends up at
`/etc/pihole/tls.pem` on the Pi-hole host (the script can do this for you; by hand, copy it
yourself).

---

## Steps
- Pros: Simple, no need to set up a CA.
- Cons: Must manually add each self-signed cert to your browser.

**Summary:** Generate a self-signed certificate and install it in your browser. You must manually trust each certificate, so this is adequate for a single server setup.

### Step 1: Create a directory to hold your cert, config, and key files:
```
mkdir -p ~/crt && cd ~/crt
```

### Step 2: Create a Certificate Configuration File (`cert.cnf`)

```
touch cert.cnf && nano cert.cnf
```

Use the [`config-templates/cert.cnf`](config-templates/cert.cnf) file in this repo as a template:
```ini
# Country Name (C)
#Organization Name (O)
#Common Name (CN) - Set this to your server's hostname or IP address.

# SAN (Subject Alternative Name), [alt-names] is required
# You can add as many hostname and IP entries as you wish

[req]
default_md = sha256
distinguished_name = req_distinguished_name
req_extensions = v3_ext
x509_extensions = v3_ext
prompt = no

[req_distinguished_name]
C = US
O = My Homelab
CN = pi.hole

[v3_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = pi.hole                 # Default pihole hostname
DNS.2 = pihole-test             # Replace with your server's hostname
DNS.3 = pihole-test.home.arpa   # Replace with your server's FQDN
IP.1 = 10.10.10.115             # Replace with your Pi-hole IP
IP.2 = 10.10.10.116             # Another local IP if needed
```

### Step 3: Generate a key and Self-Signed Certificate
Use **Elliptic Curve Digital Signature Algorithm (ECDSA)** to generate both the **private key** (`tls.key`) and the **Self-Signed Certificate** (`tls.crt`). 
```
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 -keyout tls.key -out tls.crt -config cert.cnf

```

- `x509`: Creates a self-signed certificate.
- `-newkey ec`: Creates a new Elliptic Curve (EC) key.
- `-pkeyopt ec_paramgen_curve:prime256v1`: Uses P-256 (NIST prime256v1) curve.
- `-nodes`: Skips password protection.
- `-days 365`: Valid for 365 days (1 year).
- `-keyout tls.key`: Saves the private key.
- `-out tls.crt`: Saves the self-signed certificate.
- `-config cert.cnf` Uses cert configuration file `cert.cnf` defined above.

### Step 4: Create a Combined `tls.pem` File
```
cat tls.crt tls.key | tee tls.pem
```

### Step 5: [On Pi-hole Server] Remove existing pi-hole self-signed cert files:
```
sudo rm /etc/pihole/tls*
```

### Step 6: [On Pi-hole Server] Copy `tls.pem` (cert+private key) to Pi-hole directory
```
sudo cp tls.pem /etc/pihole
```

> **Note:** This overwrites Pi-hole's default certificate at `/etc/pihole/tls.pem`, which works because `webserver.tls.cert` in `/etc/pihole/pihole.toml` points there by default. Alternatively, copy `tls.pem` to any location readable by the `pihole` user and set `webserver.tls.cert` to that path before restarting.

### Step 7. [On Pi-hole Server] Restart Pi-hole
```
sudo service pihole-FTL restart
```

> Running Pi-hole in Docker? See [Deploy the certificate](README.md#deploy-the-certificate) in
> the README — use `docker cp` instead of copying to `/etc/pihole`.

### Step 8: Import the certificate into your browser

Import `tls.crt` into your client's Trusted Root Certificate Store — see
**[Import the certificate into your browser](README.md#import-the-certificate-into-your-browser)**
in the README. With Method 2 you must import each certificate individually.
