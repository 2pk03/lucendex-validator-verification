#!/bin/bash
set -euo pipefail

# Intelligent Validator Attestation Manager
# Detects state and either sets up or updates domain verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${HOME}/.validator-keys-secure"
PROJECT_DIR="${SCRIPT_DIR}/lucendex-validator-verification"
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

update_cloudflare_pages() {
    log_step "Updating xrp-ledger.toml on Cloudflare Pages..."
    
    if [ ! -d "$PROJECT_DIR" ]; then
        log_error "Cloudflare Pages project not found locally"
        exit 1
    fi
    
    # Check if we have offline-generated keys with attestation
    if [ -f "${KEYS_DIR}/xrp-ledger.toml" ]; then
        log_info "Using offline-generated xrp-ledger.toml with attestation"
        cp "${KEYS_DIR}/xrp-ledger.toml" "${PROJECT_DIR}/.well-known/"
    else
        # No offline keys - use current validator public key
        log_warn "No offline keys - updating with current validator public key"
        local ip=$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw validator_ip)
        local pubkey=$(ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
            "grep '^n9' /opt/rippled/rippled.cfg | head -1 | awk '{print \$1}'")
        
        if [ -z "$pubkey" ]; then
            log_error "Could not retrieve validator public key from server"
            exit 1
        fi
        
        log_info "Current validator public key: ${pubkey}"
        
        cat > "${PROJECT_DIR}/.well-known/xrp-ledger.toml" <<EOF
# Lucendex XRPL Validator Domain Verification

[[VALIDATORS]]
public_key = "${pubkey}"
network = "main"
owner_country = "MT"
server_country = "NL"
EOF
    fi
    
    # Git commit and push
    cd "$PROJECT_DIR"
    git add .well-known/xrp-ledger.toml
    git commit -m "Update xrp-ledger.toml - $(date +%Y-%m-%d)" || log_warn "No changes to commit"
    git push
    
    log_info "✓ Pushed to GitHub - Cloudflare auto-deploys in ~30 seconds"
}

setup_cloudflare_pages() {
    log_step "Setting up Cloudflare Pages for domain verification..."
    
    # Create project directory
    mkdir -p "${PROJECT_DIR}/.well-known"
    
    # Check if we have generated keys
    if [ -f "${KEYS_DIR}/xrp-ledger.toml" ]; then
        # Use offline-generated toml with attestation
        cp "${KEYS_DIR}/xrp-ledger.toml" "${PROJECT_DIR}/.well-known/"
    else
        # Fallback: get current validator key from server
        log_warn "No offline keys found - using current validator key"
        local ip=$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw validator_ip)
        local pubkey=$(ssh -i "${SCRIPT_DIR}/terraform/validator_ssh_key" root@"${ip}" \
            "grep '^n9' /opt/rippled/rippled.cfg | head -1 | awk '{print \$1}'")
        
        if [ -z "$pubkey" ]; then
            log_error "Could not retrieve validator public key from server"
            exit 1
        fi
        
        cat > "${PROJECT_DIR}/.well-known/xrp-ledger.toml" <<EOF
# Lucendex XRPL Validator Domain Verification

[[VALIDATORS]]
public_key = "${pubkey}"
network = "main"
owner_country = "MT"
server_country = "NL"
EOF
    fi
    
    # Create README
    cat > "${PROJECT_DIR}/README.md" <<EOF
# Lucendex Validator Verification

XRPL domain verification for Lucendex validator.

**Verification URL:** https://${DOMAIN}/.well-known/xrp-ledger.toml
EOF
    
    # Git init
    cd "$PROJECT_DIR"
    git init
    git add .
    git commit -m "Initial commit: Lucendex validator domain verification"
    
    # GitHub setup - check if saved
    local envrc_file="${SCRIPT_DIR}/.envrc.cloudflare"
    local repo_url=""
    
    if [ -f "$envrc_file" ]; then
        source "$envrc_file"
        repo_url="${GITHUB_REPO_URL:-}"
    fi
    
    if [ -z "$repo_url" ]; then
        echo ""
        log_warn "GitHub repository must be PUBLIC for Cloudflare Pages free tier"
        log_info "Repository: git@github.com:2pk03/lucendex-validator-verification.git"
        echo ""
        
        read -p "Use this repo? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            read -p "Enter repo URL: " repo_url
        else
            repo_url="git@github.com:2pk03/lucendex-validator-verification.git"
        fi
        
        # Save to envrc
        echo "export GITHUB_REPO_URL=\"${repo_url}\"" >> "$envrc_file"
        log_info "✓ Repo URL saved"
    else
        log_info "Using saved repo: ${repo_url}"
    fi
    
    git remote add origin "$repo_url" 2>/dev/null || git remote set-url origin "$repo_url"
    git branch -M main
    git push -u origin main
    
    # Cloudflare Pages setup
    echo ""
    log_step "Cloudflare Pages Configuration"
    log_info "  1. Open: https://dash.cloudflare.com → Pages"
    log_info "  2. Create application → Connect to Git"
    log_info "  3. Select: lucendex-validator-verification"
    log_info "  4. Build: NONE (leave empty)"
    log_info "  5. Output: /"
    log_info "  6. Deploy"
    log_info "  7. Custom domains → Add: ${DOMAIN}"
    echo ""
    
    read -p "Press Enter when deployed and custom domain configured..."
    
    log_info "✓ Cloudflare Pages setup complete"
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
    
    # Check current state
    if check_domain; then
        # Domain verification exists
        if check_attestation; then
            log_info "Production attestation already configured"
            read -p "Update anyway? (y/N) " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "No changes made"
                exit 0
            fi
        else
            log_warn "Upgrading to production attestation..."
        fi
        
        # Update path
        check_existing_keys
        update_cloudflare_pages
        verify_deployment
    else
        # Setup path
        log_info "Initial setup required"
        check_existing_keys
        setup_cloudflare_pages
        verify_deployment
    fi
    
    show_summary
}

main "$@"
