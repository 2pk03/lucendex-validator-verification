#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Checking rippled versions..."

# Get latest stable release
log_info "Fetching latest stable release from GitHub..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/XRPLF/rippled/releases/latest | jq -r '.tag_name')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    log_error "Failed to fetch latest version"
    exit 1
fi

log_info "Latest stable: $LATEST_VERSION"
echo ""

# Check installed versions
log_info "Checking installed versions..."

# Validator
VALIDATOR_VERSION=$(cd infra/validator && ssh -i terraform/validator_ssh_key root@$(cd terraform && terraform output -raw validator_ip 2>/dev/null) 'docker exec rippled /opt/ripple/bin/rippled --version 2>/dev/null | head -1' 2>/dev/null || echo "Not deployed")

# Data-services API
API_VERSION=$(cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$(cd terraform && terraform output -raw data_services_ip 2>/dev/null) 'docker exec lucendex-rippled-api /opt/ripple/bin/rippled --version 2>/dev/null | head -1' 2>/dev/null || echo "Not deployed")

# Data-services History
HISTORY_VERSION=$(cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$(cd terraform && terraform output -raw data_services_ip 2>/dev/null) 'docker exec lucendex-rippled-history /opt/ripple/bin/rippled --version 2>/dev/null | head -1' 2>/dev/null || echo "Not deployed")

echo "Validator:        $VALIDATOR_VERSION"
echo "API Node:         $API_VERSION"
echo "History Node:     $HISTORY_VERSION"
echo ""

# Check if update needed
NEEDS_UPDATE=false
for version in "$VALIDATOR_VERSION" "$API_VERSION" "$HISTORY_VERSION"; do
    if [[ "$version" != *"$LATEST_VERSION"* ]] && [[ "$version" != "Not deployed" ]]; then
        NEEDS_UPDATE=true
        break
    fi
done

if [ "$NEEDS_UPDATE" = false ]; then
    log_info "✓ All nodes already running latest version ($LATEST_VERSION)"
    exit 0
fi

# Prompt for update
log_warn "Update available: $LATEST_VERSION"
read -p "Update all nodes to $LATEST_VERSION? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
    log_warn "Update cancelled"
    exit 0
fi

# Get digest
log_info "Pulling rippleci/rippled:$LATEST_VERSION to get digest..."
DIGEST=$(docker pull rippleci/rippled:$LATEST_VERSION 2>&1 | grep "Digest:" | awk '{print $2}')

if [ -z "$DIGEST" ]; then
    log_error "Failed to get digest"
    exit 1
fi

log_info "Digest: $DIGEST"

# Update compose files
log_info "Updating docker-compose.yml files..."
sed -i.bak "s|image: rippleci/rippled@sha256:.*|image: rippleci/rippled@$DIGEST|g" infra/validator/docker/docker-compose.yml
sed -i.bak "s|image: rippleci/rippled@sha256:.*|image: rippleci/rippled@$DIGEST|g" infra/data-services/docker/docker-compose.yml

log_info "✓ All compose files updated to $LATEST_VERSION"
log_warn "Deploy changes:"
log_warn "  Validator: cd infra/validator && make validator-update"
log_warn "  Data-services: cd infra/data-services && scp docker/docker-compose.yml ... && docker compose up -d"
