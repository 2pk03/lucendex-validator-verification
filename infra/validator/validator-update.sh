#!/bin/bash
set -euo pipefail

# XRPL Validator Update Script
# Updates configuration, rotates keys, or restarts validator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
DOCKER_DIR="${SCRIPT_DIR}/docker"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_validator_ip() {
    cd "${TERRAFORM_DIR}"
    terraform output -raw validator_ip 2>/dev/null || echo ""
}

check_deployment() {
    local ip=$(get_validator_ip)
    
    if [ -z "$ip" ]; then
        log_error "No validator deployed. Run validator-deploy.sh first."
        exit 1
    fi
    
    log_info "Found validator at: ${ip}"
}

update_config() {
    log_info "Updating rippled configuration..."
    
    local ip=$(get_validator_ip)
    
    # Backup current config on server
    ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "cp /opt/rippled/rippled.cfg /opt/rippled/rippled.cfg.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Upload new config
    scp -i "${TERRAFORM_DIR}/validator_ssh_key" \
        "${DOCKER_DIR}/rippled.cfg" \
        root@"${ip}":/opt/rippled/
    
    log_info "✓ Configuration updated"
}

wait_for_rippled() {
    local ip=$1
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for rippled to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if container is running (not restarting)
        if ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
               "docker ps --filter name=rippled --filter status=running | grep -q rippled" 2>/dev/null; then
            # Container is running, check if rippled is responding
            if ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
                   "docker exec validator /opt/ripple/bin/rippled server_info" &>/dev/null; then
                log_info "✓ rippled is ready"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    log_error "rippled failed to start properly"
    log_info "Check logs with: make logs"
    return 1
}

restart_validator() {
    log_info "Restarting validator..."
    
    local ip=$(get_validator_ip)
    
    ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "cd /opt/rippled && docker-compose restart"
    
    wait_for_rippled "${ip}"
    
    log_info "✓ Validator restarted"
}

rotate_keys() {
    log_info "Rotating validator keys..."
    log_warn "WARNING: This will generate new validator keys"
    log_warn "You must save the new keys and update your UNL registration"
    echo ""
    
    read -p "Continue with key rotation? (yes/NO) " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Key rotation cancelled"
        return
    fi
    
    local ip=$(get_validator_ip)
    
    # Backup current config
    ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "cp /opt/rippled/rippled.cfg /opt/rippled/rippled.cfg.backup-rotation-$(date +%Y%m%d_%H%M%S)"
    
    # Generate new keys using rippled's built-in command
    log_info "Generating new validator keys..."
    local keys_output=$(ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "docker exec validator /opt/ripple/bin/rippled validation_create")
    
    echo "$keys_output"
    
    local pubkey=$(echo "$keys_output" | jq -r '.result.validation_public_key')
    local secret=$(echo "$keys_output" | jq -r '.result.validation_seed')
    
    log_warn "IMPORTANT: Save these keys securely!"
    echo ""
    echo "New Validation Public Key: ${pubkey}"
    echo "New Validation Seed: ${secret}"
    echo ""
    
    log_info "Manual steps required:"
    log_info "  1. Edit docker/rippled.cfg locally"
    log_info "  2. Replace [validation_seed] with: ${secret}"
    log_info "  3. Update [validator_keys] with: ${pubkey} = lucendex.com"
    log_info "  4. Run this script again and select option 1 (Update configuration)"
    log_info "  5. Update your UNL registration with new public key"
}

update_docker_image() {
    log_info "Updating rippled Docker image..."
    
    local ip=$(get_validator_ip)
    
    ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "cd /opt/rippled && docker-compose pull && docker-compose up -d"
    
    log_info "✓ Docker image updated"
}

check_status() {
    log_info "Checking validator status..."
    
    local ip=$(get_validator_ip)
    
    ssh -i "${TERRAFORM_DIR}/validator_ssh_key" root@"${ip}" \
        "docker exec validator /opt/ripple/bin/rippled server_info" | jq '.result.info.server_state'
}

show_menu() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "XRPL Validator Update Options"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1) Update configuration (rippled.cfg)"
    echo "2) Restart validator"
    echo "3) Update Docker image"
    echo "4) Rotate validator keys (CAUTION)"
    echo "5) Check status"
    echo "6) Exit"
    echo ""
}

main() {
    log_info "XRPL Validator Update Tool"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    check_deployment
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                update_config
                restart_validator
                check_status
                ;;
            2)
                restart_validator
                check_status
                ;;
            3)
                update_docker_image
                check_status
                ;;
            4)
                rotate_keys
                ;;
            5)
                check_status
                ;;
            6)
                log_info "Exiting"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

main "$@"
