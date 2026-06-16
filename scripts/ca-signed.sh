#!/usr/bin/env bash
#
# ca-signed.sh
#
# Automates the Internal CA method from the Pi-hole v6 SSL guide:
#   Create an Internal Certificate Authority (CA), sign a server certificate,
#   combine into tls.pem, and optionally deploy to Pi-hole.
#
# Steps automated (from README):
#   1. Create working directory
#   2. Create CA key + certificate
#   3. Generate cert.cnf from user input
#   4. Generate server key + CSR
#   5. Sign CSR with the CA
#   6. Create combined tls.pem
#   7-9. (Optional) Deploy to Pi-hole and restart
#
# What is NOT automated:
#   Step 10 - Importing homelabCA.crt into your browser (manual).
#             See the README for instructions.
#
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
WORK_DIR="${HOME}/crt"
CA_DAYS=3650
CERT_DAYS=365
CA_COUNTRY="US"
CA_ORG="My Homelab CA"
CA_CN="MyHomelabCA"
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
    read -erp "$(printf "${CYAN}?${NC} %s [%s]: " "$prompt_text" "$default")" input
    printf -v "$var_name" '%s' "${input:-$default}"
}

# ── IP address validation ─────────────────────────────────────────────────────
valid_ip() {
    local ip="$1"
    # IPv6 (contains a colon): let openssl validate it
    [[ "$ip" == *:* ]] && return 0
    # IPv4: four 0-255 octets
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1}"; do
        (( 10#$o <= 255 )) || return 1
    done
    return 0
}

# ── Deploy helpers ────────────────────────────────────────────────────────────
print_host_recipe() {
    echo "  sudo rm -f ${PIHOLE_TLS_DIR}/tls*"
    echo "  sudo cp ${WORK_DIR}/tls.pem ${PIHOLE_TLS_DIR}"
    echo "  sudo service pihole-FTL restart"
}

print_docker_recipe() {
    local container="${1:-pihole}"
    echo "  docker cp ${WORK_DIR}/tls.pem ${container}:${PIHOLE_TLS_DIR}/tls.pem"
    echo "  docker restart ${container}"
}

deploy_host() {
    info "Removing existing Pi-hole TLS files in ${PIHOLE_TLS_DIR}"
    sudo rm -f "${PIHOLE_TLS_DIR}"/tls*
    info "Copying tls.pem to ${PIHOLE_TLS_DIR}"
    sudo cp tls.pem "${PIHOLE_TLS_DIR}"
    info "Restarting Pi-hole (pihole-FTL)"
    sudo service pihole-FTL restart
    ok "Deployed to ${PIHOLE_TLS_DIR} and restarted pihole-FTL."
}

deploy_docker() {
    if ! command -v docker &>/dev/null; then
        err "docker is not installed or not in PATH; cannot deploy to a container."
        warn "To deploy to your container manually, run:"
        print_docker_recipe "pihole"
        return
    fi

    info "Running containers (use a NAME or ID below; Compose users: the 'container_name' value):"
    docker ps --format '  {{.Names}}\t{{.Image}}\t{{.ID}}' || true

    local container
    prompt container "Pi-hole container name or ID" "pihole"

    if ! docker inspect "$container" &>/dev/null; then
        err "No Docker container '${container}' found. See the list above."
        warn "To deploy once the container is running, run:"
        print_docker_recipe "$container"
        return
    fi

    info "Copying tls.pem into container '${container}' (${PIHOLE_TLS_DIR}/tls.pem)"
    if ! docker cp tls.pem "${container}:${PIHOLE_TLS_DIR}/tls.pem"; then
        err "docker cp failed."
        warn "To deploy manually, run:"
        print_docker_recipe "$container"
        return
    fi
    info "Restarting container '${container}'"
    if ! docker restart "$container" >/dev/null; then
        err "docker restart failed."
        warn "Restart it manually with: docker restart ${container}"
        return
    fi
    ok "Deployed to container '${container}' and restarted it."
}

# ── Collect user input ────────────────────────────────────────────────────────
collect_input() {
    echo ""
    info "── CA Configuration ──"
    prompt CA_COUNTRY  "CA Country Code"       "$CA_COUNTRY"
    prompt CA_ORG      "CA Organization Name"  "$CA_ORG"
    prompt CA_CN       "CA Common Name"        "$CA_CN"
    prompt CA_DAYS     "CA Validity (days)"    "$CA_DAYS"

    echo ""
    info "── Server Certificate Configuration ──"
    prompt CERT_COUNTRY "Server Country Code"       "$CERT_COUNTRY"
    prompt CERT_ORG     "Server Organization Name"  "$CERT_ORG"
    prompt CERT_CN      "Server Common Name"        "$CERT_CN"
    prompt CERT_DAYS    "Certificate Validity (days)" "$CERT_DAYS"

    echo ""
    info "── Subject Alternative Names (SANs) ──"
    echo "  Enter DNS names one per line. Press Enter on an empty line when done."
    echo "  (pi.hole is always included as DNS.1)"
    DNS_ENTRIES=("pi.hole")
    local idx=2
    while true; do
        local entry
        read -erp "$(printf "${CYAN}?${NC} DNS.%d: " "$idx")" entry
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
        read -erp "$(printf "${CYAN}?${NC} IP.%d: " "$idx")" entry
        [[ -z "$entry" ]] && break
        if ! valid_ip "$entry"; then
            warn "Not a valid IP address: '${entry}'. Try again (or press Enter to finish)."
            continue
        fi
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
        if ((${#IP_ENTRIES[@]})); then
            i=1
            for ip in "${IP_ENTRIES[@]}"; do
                echo "IP.${i} = ${ip}"
                ((i++))
            done
        fi
    } > "$cnf_file"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    info "── Summary ──"
    echo "  Working directory : $WORK_DIR"
    echo "  CA Subject        : /C=${CA_COUNTRY}/O=${CA_ORG}/CN=${CA_CN}"
    echo "  CA Validity       : ${CA_DAYS} days"
    echo "  Cert Subject      : /C=${CERT_COUNTRY}/O=${CERT_ORG}/CN=${CERT_CN}"
    echo "  Cert Validity     : ${CERT_DAYS} days"
    echo "  DNS SANs          : ${DNS_ENTRIES[*]}"
    echo "  IP  SANs          : ${IP_ENTRIES[*]:-none}"
    echo ""
    local confirm
    read -rp "$(printf '%bProceed? [Y/n]: %b' "$YELLOW" "$NC")" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        info "Aborted."
        exit 0
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "============================================================"
    echo "  Pi-hole v6 SSL — Internal CA"
    echo "============================================================"

    check_openssl
    collect_input
    print_summary

    # Step 1: Create working directory
    info "Step 1: Creating working directory ${WORK_DIR}"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    ok "Directory ready: ${WORK_DIR}"

    # Step 2: Create or reuse the Certificate Authority (CA)
    local create_ca=1
    if [[ -f homelabCA.key && -f homelabCA.crt ]]; then
        warn "Existing CA found in ${WORK_DIR} (homelabCA.key, homelabCA.crt)."
        local reuse_ca
        read -rp "$(printf '%bReuse this CA to sign the new certificate? [Y/n]: %b' "$YELLOW" "$NC")" reuse_ca
        if [[ ! "$reuse_ca" =~ ^[Nn] ]]; then
            create_ca=0
            ok "Reusing existing CA: homelabCA.key, homelabCA.crt"
        else
            warn "Overwriting the existing CA. Certificates previously signed by it will"
            warn "stop being trusted until the new CA is re-imported into every client."
            local confirm_overwrite
            read -rp "$(printf '%bType OVERWRITE to confirm, anything else aborts: %b' "$YELLOW" "$NC")" confirm_overwrite
            [[ "$confirm_overwrite" == "OVERWRITE" ]] || { info "Aborted."; exit 0; }
        fi
    fi

    if ((create_ca)); then
        info "Step 2: Creating Certificate Authority (CA)"
        openssl req -x509 \
            -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -nodes \
            -days "$CA_DAYS" \
            -keyout homelabCA.key \
            -out homelabCA.crt \
            -subj "/C=${CA_COUNTRY}/O=${CA_ORG}/CN=${CA_CN}"
        ok "CA created: homelabCA.key, homelabCA.crt"
    else
        info "Step 2: Using existing Certificate Authority (CA)"
    fi

    # Step 3: Generate cert.cnf
    info "Step 3: Generating cert.cnf"
    generate_cert_cnf "${WORK_DIR}/cert.cnf"
    ok "Config written: cert.cnf"

    # Step 4: Generate server key and CSR
    info "Step 4: Generating server private key and CSR"
    openssl req -new \
        -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes \
        -keyout tls.key \
        -out tls.csr \
        -config cert.cnf
    ok "Key + CSR created: tls.key, tls.csr"

    # Step 5: Sign the CSR with the CA
    info "Step 5: Signing CSR with CA"
    openssl x509 -req \
        -in tls.csr \
        -CA homelabCA.crt \
        -CAkey homelabCA.key \
        -CAcreateserial \
        -out tls.crt \
        -days "$CERT_DAYS" \
        -sha256 \
        -extfile cert.cnf \
        -extensions v3_ext
    ok "Server certificate signed: tls.crt"

    # Step 6: Create combined tls.pem
    info "Step 6: Creating combined tls.pem"
    cat tls.crt tls.key > tls.pem
    ok "Combined PEM created: tls.pem"

    # Verify the certificate
    info "Verifying certificate..."
    echo "---"
    openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true
    echo "---"

    # Deploy the certificate (optional)
    echo ""
    local deploy
    read -rp "$(printf '%bDeploy the certificate now? [y/N]: %b' "$YELLOW" "$NC")" deploy
    if [[ "$deploy" =~ ^[Yy] ]]; then
        local target
        read -rp "$(printf '%bDeploy to [h]ost (bare-metal) or [d]ocker container? [h/d]: %b' "$YELLOW" "$NC")" target
        if [[ "$target" =~ ^[Dd] ]]; then
            deploy_docker
        else
            deploy_host
        fi
    else
        warn "Skipped deployment. To deploy later, run one of:"
        echo "  Bare-metal host:"
        print_host_recipe
        echo "  Docker container (default name 'pihole'):"
        print_docker_recipe "pihole"
    fi

    # Final output
    echo ""
    echo "============================================================"
    ok "All done! Files created in: ${WORK_DIR}"
    echo ""
    echo "  homelabCA.key  - CA private key (keep secure)"
    echo "  homelabCA.crt  - CA certificate (import into browsers)"
    echo "  cert.cnf       - Certificate configuration"
    echo "  tls.key        - Server private key"
    echo "  tls.csr        - Certificate signing request"
    echo "  tls.crt        - Signed server certificate"
    echo "  tls.pem        - Combined cert+key for Pi-hole"
    echo ""
    warn "MANUAL STEP REQUIRED:"
    echo "  Import homelabCA.crt into your browser's Trusted Root"
    echo "  Certificate Store. See the README for instructions."
    echo "============================================================"
}

main "$@"
