# Pi-hole v6 SSL Certificates — Manual (openssl) Steps

> **Most people should use the scripts.** See the **[README](README.md)** for the automated
> Quick Start. This document is the by-hand `openssl` procedure that
> `scripts/method1-ca-signed.sh` and `scripts/method2-self-signed.sh` automate — useful if you
> want to understand exactly what the scripts do, or adapt the process.

## Prerequisites

Install `openssl` (see the [README Quick Start](README.md#1-install-openssl)). This guide
assumes all commands run from your home directory, and that `tls.pem` ends up at
`/etc/pihole/tls.pem` on the Pi-hole host (the script can do this for you; by hand, copy it
yourself).

---
## Method 1: Use an Internal Certificate Authority CA (Recommended)
- Pros: All future certificates are trusted once you install the CA cert.
- Cons: Requires setting up a CA.

**Summary:** Set up a CA, sign certificates for each server, and install only one CA certificate instead of trusting multiple self-signed certificates.

### Step 1: Create a directory to hold your cert, config, and key files:
```
mkdir -p ~/crt && cd ~/crt
```

### Step 2: Create a Certificate Authority (CA) Key and Certificate

The CA will be used to sign server certificates.

```
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 -keyout homelabCA.key -out homelabCA.crt -subj "/C=US/O=My Homelab CA/CN=MyHomelabCA"
```
- `x509`: Generates a self-signed certificate (for a CA).
- `newkey ec`: Creates a new EC key.
- `pkeyopt ec_paramgen_curve:prime256v1`: Uses P-256 curve.
- `nodes`: Skips password protection (optional).
- `-days 3650`: Valid for 10 years.
- `keyout homelabCA.key`: Saves the private key.
- `out homelabCA.crt`: Saves the self-signed CA certificate.
- `subj`: Provides the Distinguished Name (DN) inline:
    - `C=US`: Country
    - `O=My Homelab CA`: Organization (CA)
    - `CN=MyHomelabCA`: Common Name (CA)

The **CA key** (homelabCA.key) and **CA certificate** (homelabCA.crt) is now ready to be used to sign server certificates.

### Step 3: Create a Certificate Configuration File (`cert.cnf`)

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

### Step 4: Generate a Key and CSR

Use **Elliptic Curve Digital Signature Algorithm (ECDSA)** to generate both the **private key** (`tls.key`) and **Certificate Signing Request (CSR)** (`tls.csr`).
```
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout tls.key -out tls.csr -config cert.cnf
```
- `-newkey ec`: Creates a new EC key.
- `-pkeyopt ec_paramgen_curve:prime256v1`: Uses P-256 curve.
- `-nodes` - No password on the private key.
- `-keyout tls.key`: Saves the private key.
- `-out tls.csr`: Saves the certificate signing request (CSR).
- `-config cert.cnf`: Uses the config file for CSR details.

### Step 5: Sign the CSR with the CA

This generates your server certificate from the CSR.
```
openssl x509 -req -in tls.csr -CA homelabCA.crt -CAkey homelabCA.key -CAcreateserial -out tls.crt -days 365 -sha256 -extfile cert.cnf -extensions v3_ext
```
- `-req -in tls.csr`: Uses the Certificate Signing Request (CSR) for signing.
- `-CA homelabCA.crt -CAkey homelabCA.key`: Uses our CA to sign the certificate.
- `-CAcreateserial`:Generates a unique serial number.
- `-out tls.crt`: Saves the signed certificate.
- `-days 365`: Valid for 365 days (1 year).
- `-extfile cert.cnf` -extensions v3_ext → Includes Subject Alternative Names (SAN)s.

### Step 6: Create a Combined `tls.pem` Certificate

Creates `tls.pem` with both the server certificate and private key, in that order.
```
cat tls.crt tls.key | tee tls.pem
```

### Step 7: [On Pi-hole Server] Remove existing pi-hole self-signed cert files:
```
sudo rm /etc/pihole/tls*
```

### Step 8: [On Pi-hole Server] Copy `tls.pem` (cert+private key) to Pi-hole directory
```
sudo cp tls.pem /etc/pihole
```

> **Note:** This overwrites Pi-hole's default certificate at `/etc/pihole/tls.pem`, which works because `webserver.tls.cert` in `/etc/pihole/pihole.toml` points there by default. Alternatively, copy `tls.pem` to any location readable by the `pihole` user and set `webserver.tls.cert` to that path before restarting.

### Step 9. [On Pi-hole Server] Restart Pi-hole
```
sudo service pihole-FTL restart
```

### Step 10: Import the CA into your browser

Import `homelabCA.crt` into your client's Trusted Root Certificate Store — see
**[Import the certificate into your browser](README.md#import-the-certificate-into-your-browser)**
in the README. With Method 1 you import the CA once; all certificates it signs are then trusted.

### Issuing additional server certificates with your CA (Optional)
You can issue additional certificates for your other servers using the CA you created in **step 2**, and you do not have to re-install the CA certificate in your browser. 
Just run the commands listed in **steps 4 and 5** again:

```
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout tls2.key -out tls2.csr -config cert2.cnf
```
```
openssl x509 -req -in tls.csr -CA homelabCA.crt -CAkey homelabCA.key -CAcreateserial -out tls2.crt -days 365 -sha256 -extfile cert2.cnf -extensions v3_ext
```

---

## Method 2: Use a Self-Signed Certificate and Manually Trust It
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

### Step 8: Import the certificate into your browser

Import `tls.crt` into your client's Trusted Root Certificate Store — see
**[Import the certificate into your browser](README.md#import-the-certificate-into-your-browser)**
in the README. With Method 2 you must import each certificate individually.
