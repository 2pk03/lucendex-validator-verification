#!/bin/bash
set -euo pipefail

# Verify rippled Docker image authenticity and integrity
# SECURITY: Run this before deploying or updating validator

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Official rippled image details (update these from official sources)
OFFICIAL_REPO="rippleci/rippled"
RECOMMENDED_TAG="2.3.0"  # Update to latest stable version
OFFICIAL_DIGEST="sha256:467dde2bf955dba05aafb2f6020bfd8eacf64cd07305b41d7dfc3c8e12df342d"

# Official sources for verification
OFFICIAL_DOCKERHUB="https://hub.docker.com/r/rippleci/rippled/tags"
OFFICIAL_GITHUB="https://github.com/XRPLF/rippled/releases"
OFFICIAL_DOCS="https://xrpl.org/install-rippled-on-ubuntu.html"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "rippled Docker Image Security Verification"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Check if Docker Content Trust is enabled
log_info "Step 1: Checking Docker Content Trust..."
if [ "${DOCKER_CONTENT_TRUST:-0}" = "1" ]; then
    log_info "✓ Docker Content Trust is ENABLED"
else
    log_warn "⚠️  Docker Content Trust is DISABLED"
    log_warn "To enable: export DOCKER_CONTENT_TRUST=1"
fi
echo ""

# Step 2: Get current image info
log_info "Step 2: Checking for existing rippled image..."
if docker image inspect "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" &>/dev/null; then
    CURRENT_DIGEST=$(docker image inspect "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" --format='{{index .RepoDigests 0}}' | cut -d'@' -f2)
    log_info "Current image digest: ${CURRENT_DIGEST}"
else
    log_warn "Image not found locally"
    CURRENT_DIGEST=""
fi
echo ""

# Step 3: Pull image with digest verification
log_info "Step 3: Pulling verified rippled image..."
log_info "Repository: ${OFFICIAL_REPO}"
log_info "Tag: ${RECOMMENDED_TAG}"
log_info "Expected digest: ${OFFICIAL_DIGEST}"
echo ""

# Pull with specific digest to ensure integrity
if docker pull "${OFFICIAL_REPO}@${OFFICIAL_DIGEST}"; then
    log_info "✓ Image pulled and verified successfully"
    
    # Tag it with version for easier reference
    docker tag "${OFFICIAL_REPO}@${OFFICIAL_DIGEST}" "${OFFICIAL_REPO}:${RECOMMENDED_TAG}"
    log_info "✓ Tagged as ${OFFICIAL_REPO}:${RECOMMENDED_TAG}"
else
    log_error "Failed to pull image with digest verification"
    exit 1
fi
echo ""

# Step 4: Verify image details
log_info "Step 4: Verifying image details..."
IMAGE_ID=$(docker image inspect "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" --format='{{.Id}}')
IMAGE_CREATED=$(docker image inspect "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" --format='{{.Created}}')
IMAGE_SIZE=$(docker image inspect "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" --format='{{.Size}}' | awk '{printf "%.2f MB", $1/1024/1024}')

log_info "Image ID: ${IMAGE_ID}"
log_info "Created: ${IMAGE_CREATED}"
log_info "Size: ${IMAGE_SIZE}"
echo ""

# Step 5: Security scan (if available)
log_info "Step 5: Running security scan..."
if command -v docker &>/dev/null; then
    # Try Docker Scout (new) or docker scan (old)
    if docker scout version &>/dev/null 2>&1; then
        log_info "Running Docker Scout scan..."
        if docker scout cves "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" --only-severity critical,high 2>/dev/null; then
            log_info "✓ Scout scan complete"
        else
            log_warn "⚠️  Could not complete Scout scan (may need authentication)"
        fi
    elif docker scan --version &>/dev/null 2>&1; then
        log_info "Running Docker scan..."
        if docker scan "${OFFICIAL_REPO}:${RECOMMENDED_TAG}" 2>/dev/null; then
            log_info "✓ No high-severity vulnerabilities found"
        else
            log_warn "⚠️  Could not complete scan"
        fi
    else
        log_warn "Docker vulnerability scanning not available"
        log_warn "Consider using: trivy image ${OFFICIAL_REPO}:${RECOMMENDED_TAG}"
    fi
else
    log_warn "Docker scan not available"
fi
echo ""

# Step 6: Verify against official sources
log_info "Step 6: Manual verification steps..."
log_warn "IMPORTANT: Always verify image digest against official sources:"
echo ""
echo "  1. Docker Hub (Official):"
echo "     ${OFFICIAL_DOCKERHUB}"
echo ""
echo "  2. GitHub Releases (rippled source):"
echo "     ${OFFICIAL_GITHUB}"
echo ""
echo "  3. XRPL Documentation:"
echo "     ${OFFICIAL_DOCS}"
echo ""
log_warn "Compare the digest shown above with official sources!"
echo ""

# Step 7: Summary
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "✅ Image Verification Complete!"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Verified image: ${OFFICIAL_REPO}:${RECOMMENDED_TAG}"
log_info "SHA256 digest: ${OFFICIAL_DIGEST}"
echo ""
log_info "Next steps:"
log_info "  1. Update docker-compose.yml with verified digest"
log_info "  2. Deploy validator: ./validator-deploy.sh"
log_info "  3. Verify deployment: make status"
echo ""
log_warn "⚠️  Security Checklist:"
echo "  • Verified digest matches official Docker Hub"
echo "  • Checked GitHub releases for authenticity"
echo "  • Reviewed vulnerability scan results"
echo "  • Enabled Docker Content Trust (recommended)"
echo ""
