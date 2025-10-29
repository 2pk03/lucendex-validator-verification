.PHONY: help ssh status logs health peers consensus restart stop start deploy destroy clean backup restore

# Get validator IP from Terraform
VALIDATOR_IP := $(shell cd terraform && terraform output -raw validator_ip 2>/dev/null || echo "not-deployed")
SSH_KEY := terraform/validator_ssh_key
SSH_CMD := ssh -i $(SSH_KEY) root@$(VALIDATOR_IP)

help: ## Show this help message
	@echo "XRPL Validator Management Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

ssh: ## SSH into validator
	@$(SSH_CMD)

status: ## Check validator status
	@echo "Checking validator status..."
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" | jq '.result.info.server_state'

logs: ## View rippled logs (follow mode)
	@echo "Following rippled logs (Ctrl+C to exit)..."
	@$(SSH_CMD) "docker logs -f rippled"

logs-tail: ## View last 100 lines of rippled logs
	@$(SSH_CMD) "docker logs --tail 100 rippled"

health: ## Check validator health
	@echo "Validator Health Check"
	@echo "====================="
	@echo "Server State:"
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" | jq -r '.result.info.server_state'
	@echo ""
	@echo "Ledger Index:"
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" | jq -r '.result.info.validated_ledger.seq'
	@echo ""
	@echo "Peer Count:"
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled peers" | jq '.result.peers | length'

peers: ## Show connected peers
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled peers" | jq -e '.result.peers[]? | {address, type, version}' || echo "No peer data available (rippled may still be starting)"

consensus: ## Show consensus participation
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled consensus_info"

ledger: ## Show current ledger info
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" | jq '.result.info.validated_ledger'

restart: ## Restart rippled container
	@echo "Restarting rippled..."
	@$(SSH_CMD) "cd /opt/rippled && docker-compose restart"
	@echo "✓ Rippled restarted"

stop: ## Stop rippled container
	@echo "Stopping rippled..."
	@$(SSH_CMD) "cd /opt/rippled && docker-compose stop"
	@echo "✓ Rippled stopped"

start: ## Start rippled container
	@echo "Starting rippled..."
	@$(SSH_CMD) "cd /opt/rippled && docker-compose start"
	@echo "✓ Rippled started"

resources: ## Check VM resource usage
	@echo "CPU and Memory Usage:"
	@$(SSH_CMD) "top -bn1 | head -5"
	@echo ""
	@echo "Disk Usage:"
	@$(SSH_CMD) "df -h /"
	@echo ""
	@echo "Docker Stats:"
	@$(SSH_CMD) "docker stats --no-stream rippled"

disk: ## Check disk usage
	@$(SSH_CMD) "df -h"

updates: ## Check for system updates
	@echo "Checking for updates..."
	@$(SSH_CMD) "apt update && apt list --upgradable"

firewall-status: ## Show firewall status
	@$(SSH_CMD) "ufw status verbose"

test-connectivity: ## Test XRPL peer connectivity
	@echo "Testing peer connectivity on port 51235..."
	@nc -zv $(VALIDATOR_IP) 51235 || echo "Port not reachable"

backup: ## Backup validator configuration
	@echo "Creating backup..."
	@mkdir -p backups/$$(date +%Y%m%d_%H%M%S)
	@scp -i $(SSH_KEY) root@$(VALIDATOR_IP):/opt/rippled/rippled.cfg backups/$$(date +%Y%m%d_%H%M%S)/
	@scp -i $(SSH_KEY) root@$(VALIDATOR_IP):/opt/rippled/docker-compose.yml backups/$$(date +%Y%m%d_%H%M%S)/
	@echo "✓ Backup saved to backups/$$(date +%Y%m%d_%H%M%S)/"

verify-backup: ## Verify latest backup integrity
	@echo "Verifying backup integrity..."
	@ls -lh backups/$$(ls -t backups | head -1)

update-config: ## Update rippled configuration
	@echo "Uploading new configuration..."
	@scp -i $(SSH_KEY) docker/rippled.cfg root@$(VALIDATOR_IP):/opt/rippled/
	@echo "Configuration updated. Restart required: make restart"

verify-image: ## Verify rippled Docker image authenticity
	@./scripts/verify-rippled-image.sh

deploy: ## Run deployment script
	@./deploy.sh

destroy: ## Destroy infrastructure (WARNING: irreversible)
	@echo "WARNING: This will destroy all infrastructure!"
	@read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ]
	@cd terraform && terraform destroy
	@echo "✓ Infrastructure destroyed"

clean: ## Clean local artifacts
	@rm -rf terraform/.terraform
	@rm -f terraform/*.tfstate*
	@rm -f terraform/tfplan
	@echo "✓ Local artifacts cleaned"

validator-keys: ## Show validator public key
	@echo "Fetching validator public key from rippled.cfg..."
	@$(SSH_CMD) "grep '^n9' /opt/rippled/rippled.cfg | head -1 | awk '{print \$1}'"

validator-id: ## Show validator ID (public key)
	@echo "Validator ID (Public Key):"
	@$(SSH_CMD) "grep '^n9' /opt/rippled/rippled.cfg | head -1 | awk '{print \$1}'"
	@echo ""
	@echo "Validation Seed (Secret - DO NOT SHARE):"
	@$(SSH_CMD) "grep -A 1 '^\[validation_seed\]' /opt/rippled/rippled.cfg | tail -1"
	@echo ""
	@echo "Use public key for:"
	@echo "  - UNL registration"
	@echo "  - DNS TXT record (xrpl-validator-public-key.lucendex.com)"

get-config: ## Get full rippled configuration
	@echo "=== rippled.cfg ==="
	@$(SSH_CMD) "cat /opt/rippled/rippled.cfg"

get-pubkey: ## Get validator public key only (from API)
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null | jq -r '.result.info.pubkey_validator // empty'"

get-seed: ## Get validation seed from config (PRIVATE!)
	@echo "⚠️  WARNING: This is your PRIVATE validation seed!"
	@echo "⚠️  NEVER share this with anyone!"
	@echo ""
	@$(SSH_CMD) "grep -A 1 '^\[validation_seed\]' /opt/rippled/rippled.cfg 2>/dev/null | tail -1 | xargs || echo 'No validation_seed in config (validator in tracking mode)'"

get-keys: ## Get both public key and seed
	@echo "=== Validator Keys ==="
	@echo ""
	@echo "Public Key (from running validator):"
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null | jq -r '.result.info.pubkey_validator // \"Not validating (tracking mode)\"'"
	@echo ""
	@echo "Validation Seed (from config - ⚠️  PRIVATE!):"
	@$(SSH_CMD) "grep -A 1 '^\[validation_seed\]' /opt/rippled/rippled.cfg 2>/dev/null | tail -1 | xargs || echo 'No validation_seed in config'"
	@echo ""
	@echo "Note: If no seed in config, validator is in tracking mode (not validating)"
	@echo ""

version: ## Show rippled version
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled --version"

info: ## Show deployment info
	@echo "Validator Information"
	@echo "===================="
	@echo "IP Address: $(VALIDATOR_IP)"
	@echo "SSH Key: $(SSH_KEY)"
	@echo "SSH Command: $(SSH_CMD)"
	@echo ""
	@echo "Quick access: make ssh"
