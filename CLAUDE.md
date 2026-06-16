# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A guide + automation layer for creating custom SSL certificates for **Pi-hole v6**, whose
embedded web server (no more `lighttpd`) requires a PEM file containing both the cert and
private key at `/etc/pihole/tls.pem`. There is no build system, test suite, or package
manager — the deliverables are Markdown docs and two interactive Bash scripts.

It documents two methods; the **Internal CA** method is the recommended, primary path:

- **Internal CA (recommended):** stand up an internal CA, sign a server cert with it, import the
  CA cert into the browser once. Script: `scripts/ca-signed.sh`. Guide: `README.md`.
- **Self-signed (alternative):** generate a single self-signed cert, import it per-machine.
  Script: `scripts/self-signed.sh`. Guide: `self-signed.md`.

Both use ECDSA P-256 keys and produce the combined `tls.pem`. The scripts automate everything
on the Pi-hole host — cert generation, optional deploy to **bare-metal** (`sudo cp` +
`service pihole-FTL restart`) or **Docker** (`docker cp` + `docker restart`), with CA reuse on
re-runs. The only manual step is importing the cert/CA into the client browser (see `README.md`).

## Doc Layout (keep these in sync)

- `README.md` — the Internal CA walkthrough (PRIMARY). Owns the canonical **Deploy the
  certificate** and **Import the certificate into your browser** sections; other docs link to
  those anchors (`#deploy-the-certificate`, `#import-the-certificate-into-your-browser`).
- `self-signed.md` — the demoted self-signed path; links back to the README for deploy/import.
- `manual-openssl-ca.md` / `manual-openssl-self-signed.md` — the by-hand `openssl` steps per
  method.

This repo is **canonical**. An older gist
(`gist.github.com/kaczmar2/e1b5eb635c1a1e792faf36508c5698ee`) is frozen as a pointer here — do
not edit it; make changes in this repo only.

## Conventions

- Keep it **generic/public-safe**: IPs like `10.10.10.115` and hostnames like
  `pihole-test.home.arpa` are "replace with your…" placeholders, not real homelab values.
- `tls.pem` must be **cert-then-key** (`cat tls.crt tls.key`).
- The two scripts share near-identical structure (color helpers, `prompt`/`collect_input`,
  `valid_ip`, `generate_cert_cnf`, the deploy helpers + two-step deploy gate). **Edit both in
  parallel to keep them identical** where they overlap, and keep them `shellcheck`-clean and
  mode `100755`.
- `config-templates/cert.cnf` is the reference OpenSSL config the scripts generate at runtime;
  keep it in sync with the `generate_cert_cnf` heredocs.
- Internal planning docs live under `docs/` and are git-ignored (`docs/PUBLISH-PLAN.md`,
  `docs/superpowers/`) — never publish them.
