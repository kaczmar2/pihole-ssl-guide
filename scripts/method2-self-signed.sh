#!/usr/bin/env bash
#
# method2-self-signed.sh
#
# Automates Method 2 from the Pi-hole v6 SSL guide:
#   Generate a self-signed certificate, combine into tls.pem,
#   and optionally deploy to Pi-hole.
#
# Steps automated (from README):
#   1. Create working directory
#   2. Generate cert.cnf from user input
#   3. Generate self-signed key + certificate
#   4. Create combined tls.pem
#   5-7. (Optional) Deploy to Pi-hole and restart
#
# What is NOT automated:
#   Step 8 - Importing tls.crt into your browser (manual).
#            See SCRIPTS.md for instructions.
#
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
WORK_DIR="${HOME}/crt"
CERT_DAYS=365
CERT_COUNTRY="US"
CERT_ORG="My Homelab"
CERT_CN="pi.hole"
PIHOLE_TLS_DIR="/etc/pihole"

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# ── Prerequisite check ────────────────────────────────────────────────────────
check_openssl() {
    if ! command -v openssl &>/dev/null; then
        err "openssl is not installed. Install it first:"
        echo "  sudo apt update && sudo apt install openssl -y   # Debian/Ubuntu"
        echo "  sudo yum install openssl -y                      # RHEL/CentOS"
        echo "  sudo dnf install openssl -y                      # Fedora"
        exit 1
    fi
    ok "openssl found: $(openssl version)"
}

# ── Prompt helper (with default) ─────────────────────────────────────────────
prompt() {
    local var_name="$1" prompt_text="$2" default="$3"
    local input
    read -rp "$(printf "${CYAN}?${NC} %s [%s]: " "$prompt_text" "$default")" input
    eval "$var_name=\"${input:-$default}\""
}

# ── Collect user input ────────────────────────────────────────────────────────
collect_input() {
    echo ""
    info "── Certificate Configuration ──"
    prompt CERT_COUNTRY "Country Code"           "$CERT_COUNTRY"
    prompt CERT_ORG     "Organization Name"      "$CERT_ORG"
    prompt CERT_CN      "Common Name"            "$CERT_CN"
    prompt CERT_DAYS    "Validity (days)"        "$CERT_DAYS"

    echo ""
    info "── Subject Alternative Names (SANs) ──"
    echo "  Enter DNS names one per line. Press Enter on an empty line when done."
    echo "  (pi.hole is always included as DNS.1)"
    DNS_ENTRIES=("pi.hole")
    local idx=2
    while true; do
        local entry
        read -rp "$(printf "${CYAN}?${NC} DNS.%d: " "$idx")" entry
        [[ -z "$entry" ]] && break
        DNS_ENTRIES+=("$entry")
        ((idx++))
    done

    echo ""
    echo "  Enter IP addresses one per line. Press Enter on an empty line when done."
    IP_ENTRIES=()
    idx=1
    while true; do
        local entry
        read -rp "$(printf "${CYAN}?${NC} IP.%d: " "$idx")" entry
        [[ -z "$entry" ]] && break
        IP_ENTRIES+=("$entry")
        ((idx++))
    done

    if [[ ${#IP_ENTRIES[@]} -eq 0 ]]; then
        warn "No IP SANs provided. The certificate will only match DNS names."
    fi

    prompt WORK_DIR "Working directory" "$WORK_DIR"
}

# ── Generate cert.cnf ────────────────────────────────────────────────────────
generate_cert_cnf() {
    local cnf_file="$1"
    {
        cat <<EOF
[req]
default_md = sha256
distinguished_name = req_distinguished_name
req_extensions = v3_ext
x509_extensions = v3_ext
prompt = no

[req_distinguished_name]
C = ${CERT_COUNTRY}
O = ${CERT_ORG}
CN = ${CERT_CN}

[v3_ext]
subjectAltName = @alt_names

[alt_names]
EOF
        local i=1
        for dns in "${DNS_ENTRIES[@]}"; do
            echo "DNS.${i} = ${dns}"
            ((i++))
        done
        i=1
        for ip in "${IP_ENTRIES[@]}"; do
            echo "IP.${i} = ${ip}"
            ((i++))
        done
    } > "$cnf_file"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    info "── Summary ──"
    echo "  Working directory : $WORK_DIR"
    echo "  Cert Subject      : /C=${CERT_COUNTRY}/O=${CERT_ORG}/CN=${CERT_CN}"
    echo "  Cert Validity     : ${CERT_DAYS} days"
    echo "  DNS SANs          : ${DNS_ENTRIES[*]}"
    echo "  IP  SANs          : ${IP_ENTRIES[*]:-none}"
    echo ""
    local confirm
    read -rp "$(printf "${YELLOW}Proceed? [Y/n]: ${NC}")" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        info "Aborted."
        exit 0
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "============================================================"
    echo "  Pi-hole v6 SSL — Method 2: Self-Signed Certificate"
    echo "============================================================"

    check_openssl
    collect_input
    print_summary

    # Step 1: Create working directory
    info "Step 1: Creating working directory ${WORK_DIR}"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    ok "Directory ready: ${WORK_DIR}"

    # Step 2: Generate cert.cnf
    info "Step 2: Generating cert.cnf"
    generate_cert_cnf "${WORK_DIR}/cert.cnf"
    ok "Config written: cert.cnf"

    # Step 3: Generate key and self-signed certificate
    info "Step 3: Generating private key and self-signed certificate"
    openssl req -x509 \
        -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes \
        -days "$CERT_DAYS" \
        -keyout tls.key \
        -out tls.crt \
        -config cert.cnf
    ok "Key + certificate created: tls.key, tls.crt"

    # Step 4: Create combined tls.pem
    info "Step 4: Creating combined tls.pem"
    cat tls.crt tls.key > tls.pem
    ok "Combined PEM created: tls.pem"

    # Verify the certificate
    info "Verifying certificate..."
    echo "---"
    openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true
    echo "---"

    # Steps 5-7: Deploy to Pi-hole (optional)
    echo ""
    local deploy
    read -rp "$(printf "${YELLOW}Deploy tls.pem to Pi-hole (${PIHOLE_TLS_DIR})? [y/N]: ${NC}")" deploy
    if [[ "$deploy" =~ ^[Yy] ]]; then
        info "Step 5: Removing existing Pi-hole TLS files"
        sudo rm -f "${PIHOLE_TLS_DIR}"/tls*
        ok "Old TLS files removed"

        info "Step 6: Copying tls.pem to ${PIHOLE_TLS_DIR}"
        sudo cp tls.pem "$PIHOLE_TLS_DIR"
        ok "tls.pem deployed"

        info "Step 7: Restarting Pi-hole"
        sudo service pihole-FTL restart
        ok "Pi-hole restarted"
    else
        warn "Skipped deployment. To deploy manually, run:"
        echo "  sudo rm -f ${PIHOLE_TLS_DIR}/tls*"
        echo "  sudo cp ${WORK_DIR}/tls.pem ${PIHOLE_TLS_DIR}"
        echo "  sudo service pihole-FTL restart"
    fi

    # Final output
    echo ""
    echo "============================================================"
    ok "All done! Files created in: ${WORK_DIR}"
    echo ""
    echo "  cert.cnf  - Certificate configuration"
    echo "  tls.key   - Private key"
    echo "  tls.crt   - Self-signed certificate (import into browsers)"
    echo "  tls.pem   - Combined cert+key for Pi-hole"
    echo ""
    warn "MANUAL STEP REQUIRED:"
    echo "  Import tls.crt into your browser's Trusted Root"
    echo "  Certificate Store. See SCRIPTS.md for instructions."
    echo "============================================================"
}

main "$@"
