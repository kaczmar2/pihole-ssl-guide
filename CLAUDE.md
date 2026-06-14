# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A guide + automation layer for creating custom SSL certificates for **Pi-hole v6**, whose
embedded web server (no more `lighttpd`) requires a PEM file containing both the cert and
private key at `/etc/pihole/tls.pem`. There is no build system, test suite, or package
manager — the deliverables are Markdown docs and two interactive Bash scripts.

It documents two methods:
- **Method 1 (recommended):** stand up an internal CA, sign a server cert with it, import the
  CA cert into the browser once. `scripts/method1-ca-signed.sh`.
- **Method 2:** generate a single self-signed cert, import that cert per-machine.
  `scripts/method2-self-signed.sh`.

Both use ECDSA P-256 keys and produce the combined `tls.pem`. The scripts automate everything
on the Pi-hole server (cert generation through optional deploy + `pihole-FTL` restart); the
only manual step is importing the cert/CA into the client browser (see the README).

## The Source-of-Truth Problem (read before editing the procedure)

The certificate procedure currently exists in **three copies that drift apart**:

1. `README.md` — the written guide
2. `scripts/method1-ca-signed.sh` and `scripts/method2-self-signed.sh` — the automation
3. An external **gist** (`gist.github.com/kaczmar2/e1b5eb635c1a1e792faf36508c5698ee`, cloned
   locally at `~/repos/pihole-v6-self-signed-certs`) — the original source

**Any change to the openssl commands, step ordering, or cert layout must be applied to both
the README and the relevant script.** `docs/PUBLISH-PLAN.md` tracks the plan to make this repo
canonical and trim the gist to a pointer — read it before structural changes.

### Known bug: Method 2 cert order

`tls.pem` must be **cert-then-key** (`cat tls.crt tls.key`). Method 1 is correct everywhere.
**Method 2 still has the key-then-cert bug** (`cat tls.key tls.crt`) in two places that must
be fixed together:
- `README.md` (~line 248)
- `scripts/method2-self-signed.sh` (~line 191)

The gist was already fixed (commit `298a3e9` in `pihole-v6-self-signed-certs`). Per
`PUBLISH-PLAN.md`, fix this in the repo **before** making the repo canonical.

## Conventions

- This repo is intentionally **generic/public-safe**: IPs like `10.10.10.115` and hostnames
  like `pihole-test.home.arpa` are labeled "replace with your…" placeholders, not real homelab
  values. Keep it that way — do not introduce real network details.
- The scripts share near-identical structure (color helpers, `prompt`/`collect_input`,
  `generate_cert_cnf`, optional deploy block). Edit both in parallel to keep them consistent.
- `config-templates/cert.cnf` is the reference OpenSSL config the scripts generate at runtime;
  keep it in sync with the `generate_cert_cnf` heredocs.
