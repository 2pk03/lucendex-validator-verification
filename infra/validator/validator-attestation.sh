#!/bin/bash
set -euo pipefail

# Validator Attestation Manager
# Updates xrp-ledger.toml with validator public key
# Website deployment handled separately via infra/website/website-deploy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${HOME}/.validator-keys-secure"
WEBSITE_DIR="${SCRIPT_DIR}/../../website"
DOMAIN="lucendex.com"
TOML_URL="https://${DOMAIN}/.well-known/xrp-ledger.toml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_domain() {
    log_step "Checking domain verification status..."
    
    if curl -sf "$TOML_URL" >/dev/null 2>&1; then
        log_info "✓ Domain verification already exists"
        log_info "URL: $TOML_URL"
        return 0
    else
        log_warn "No domain verification found"
        return 1
    fi
}

check_attestation() {
    local toml_content=$(curl -sf "$TOML_URL" 2>/dev/null || echo "")
    
    if echo "$toml_content" | grep -q "attestation"; then
        log_info "✓ Production attestation present"
        return 0
    else
        log_warn "Basic setup only (no attestation)"
        return 1
    fi
}

install_validator_keys_tool() {
    if command -v validator-keys &>/dev/null; then
        log_info "✓ validator-keys-tool already installed"
        return 0
    fi
    
    log_step "Installing validator-keys-tool..."
    "${SCRIPT_DIR}/scripts/setup-validator-keys-tool.sh"
    export PATH="${HOME}/.local/bin:$PATH"
    log_info "✓ Tool installed"
}

check_existing_keys() {
    log_step "Checking for existing validator keys..."
    
    if [ ! -f "${KEYS_DIR}/public_key.txt" ]; then
        log_error "No validator keys found in ${KEYS_DIR}"
        log_error "Expected files: public_key.txt, xrp-ledger.toml"
        log_error "Generate keys first with: make validator-generate-keys"
        exit 1
    fi
    
    local pubkey=$(cat "${KEYS_DIR}/public_key.txt" | xargs)
    log_info "✓ Found validator keys"
    log_info "Public key: ${pubkey}"
    
    # Check if xrp-ledger.toml exists
    if [ ! -f "${KEYS_DIR}/xrp-ledger.toml" ]; then
        log_warn "No xrp-ledger.toml found in ${KEYS_DIR}"
        log_info "Creating from public_key.txt..."
        
        cat > "${KEYS_DIR}/xrp-ledger.toml" <<EOF
# Lucendex XRPL Validator Domain Verification
# Deploy to: https://lucendex.com/.well-known/xrp-ledger.toml

[[VALIDATORS]]
public_key = "${pubkey}"
network = "main"
owner_country = "MT"
server_country = "NL"
domain = "lucendex.com"
EOF
        log_info "✓ Created xrp-ledger.toml"
    fi
}

update_validator_config() {
    log_step "Updating validator configuration on server..."
    
    local ip=$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw validator_ip)
    
    # Check if we have offline keys
    if [ ! -f "${KEYS_DIR}/validator_token.txt" ]; then
        log_error "No validator_token.txt found in ${KEYS_DIR}"
        log_error "Run generate-offline-keys.sh first or use existing validation_seed"
        return 1
    fi
    
    local token=$(grep -A 1 '^\[validator_token\]' "${KEYS_DIR}/validator_token.txt" | tail -1 | xargs)
    local pubkey=$(cat "${KEYS_DIR}/public_key.txt" | xargs)
    
    # Validate inputs
    if [ -z "$token" ] || [ -z "$pubkey" ]; then
        log_error "Could not extract token or public key from offline keys"
        log_error "Token: '${token}'"
        log_error "Pubkey: '${pubkey}'"
        return 1
    fi
    
    # Backup current config
    ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
        "cp /opt/rippled/rippled.cfg /opt/rippled/rippled.cfg.backup-attestation-$(date +%Y%m%d_%H%M%S)"
    
    # Remove old validation config sections
    ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
        "sed -i '/^\[validator_token\]/,/^$/d; /^\[validation_seed\]/,/^$/d; /^\[validator_keys\]/,/^$/d' /opt/rippled/rippled.cfg"
    
    # Add new production config with validator_token
    ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" "cat >> /opt/rippled/rippled.cfg << 'EOF'

# Validator Configuration (Production - with attestation)
[validator_token]
EOF
echo '${token}' | ssh -i '${SCRIPT_DIR}/terraform/validator_ssh_key' root@'${ip}' 'cat >> /opt/rippled/rippled.cfg'"
    
    log_info "✓ Validator configuration updated with production keys"
    log_info "Public key: ${pubkey}"
    
    # Restart validator
    ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
        "cd /opt/rippled && docker-compose restart"
    
    log_info "✓ Validator restarted"
    log_info "Waiting for rippled to come online..."
    sleep 30
}

update_toml_file() {
    log_step "Updating xrp-ledger.toml..."
    
    # Ensure .well-known directory exists
    mkdir -p "${WEBSITE_DIR}/.well-known"
    
    # Check if we have offline-generated keys with attestation
    if [ -f "${KEYS_DIR}/xrp-ledger.toml" ]; then
        log_info "Using offline-generated xrp-ledger.toml with attestation"
        cp "${KEYS_DIR}/xrp-ledger.toml" "${WEBSITE_DIR}/.well-known/"
    else
        # No offline keys - use current validator public key
        log_warn "No offline keys - generating from current validator public key"
        local ip=$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw validator_ip)
        local pubkey=$(ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
            "grep '^n9' /opt/rippled/rippled.cfg | head -1 | awk '{print \$1}'")
        
        if [ -z "$pubkey" ]; then
            log_error "Could not retrieve validator public key from server"
            exit 1
        fi
        
        log_info "Current validator public key: ${pubkey}"
        
        cat > "${WEBSITE_DIR}/.well-known/xrp-ledger.toml" <<EOF
# Lucendex XRPL Validator Domain Verification

[[VALIDATORS]]
public_key = "${pubkey}"
network = "main"
owner_country = "MT"
server_country = "NL"
EOF
    fi
    
    log_info "✓ xrp-ledger.toml updated in ${WEBSITE_DIR}/.well-known/"
    log_info "Run 'make deploy' in infra/website/ to push to production"
}

verify_deployment() {
    log_step "Verifying deployment..."
    
    sleep 5
    
    if curl -sf "$TOML_URL" | grep -q "VALIDATORS"; then
        log_info "✅ xrp-ledger.toml accessible at: $TOML_URL"
        
        if curl -sf "$TOML_URL" | grep -q "attestation"; then
            log_info "✅ Production attestation verified!"
        else
            log_warn "⚠️  Basic setup (no attestation)"
        fi
    else
        log_warn "Could not verify - DNS may be propagating (wait 5-10 minutes)"
    fi
}

show_summary() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "🎉 Validator Attestation Complete!"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Validator Public Key:"
    cat "${KEYS_DIR}/public_key.txt" 2>/dev/null || echo "  (check with: make validator-id)"
    echo ""
    log_info "Verification URL:"
    echo "  $TOML_URL"
    echo ""
    log_info "Future updates:"
    log_info "  • Edit ~/.validator-keys/xrp-ledger.toml"
    log_info "  • Run: ./validator-attestation.sh"
    log_info "  • Auto-pushes to GitHub → Cloudflare deploys"
    echo ""
}

main() {
    log_info "Lucendex Validator Attestation Manager"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check for validator keys
    check_existing_keys
    
    # Update TOML file
    update_toml_file
    
    # Show summary
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "✓ Validator xrp-ledger.toml updated"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Next steps:"
    log_info "  1. cd infra/website"
    log_info "  2. make deploy"
    echo ""
    log_info "Verification URL: $TOML_URL"
    echo ""
}

main "$@"
