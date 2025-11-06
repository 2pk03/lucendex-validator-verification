#!/bin/bash
set -euo pipefail

# LucenDEX Website Deployment
# Pushes website content to public GitHub repo → Cloudflare Pages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_SOURCE="${SCRIPT_DIR}/../../website"
REPO_URL="git@github.com:2pk03/lucendex-validator-verification.git"
TEMP_DIR="/tmp/lucendex-website-deploy"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

log_info "LucenDEX Website Deployment"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean up any existing temp directory
if [ -d "$TEMP_DIR" ]; then
    log_step "Cleaning up previous deployment..."
    rm -rf "$TEMP_DIR"
fi

# Clone public repo
log_step "Cloning public repository..."
git clone "$REPO_URL" "$TEMP_DIR"

# Copy website content
log_step "Copying website content..."
rsync -av --delete \
    --exclude='.git' \
    --exclude='deploy.sh' \
    "${WEBSITE_SOURCE}/" "${TEMP_DIR}/"

# Git operations
cd "$TEMP_DIR"

log_step "Staging changes..."
git add .

log_step "Committing changes..."
if git commit -m "Website update - $(date +%Y-%m-%d\ %H:%M)"; then
    log_step "Pushing to GitHub..."
    git push origin main
    log_info "✓ Website deployed successfully"
    log_info "Cloudflare Pages will auto-deploy in ~30 seconds"
else
    log_warn "No changes to deploy"
fi

# Cleanup
log_step "Cleaning up..."
cd - > /dev/null
rm -rf "$TEMP_DIR"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "✓ Deployment complete"
log_info "Live URL: https://lucendex.com"
