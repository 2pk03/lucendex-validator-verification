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

status: ## Check validator status (enhanced)
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" \
		| jq '.result.info | {server_state, time, complete_ledgers, peers, pubkey_validator, last_close, load_factor, io_latency_ms}'

sync-status: ## Check ledger sync progress
	@echo "=== Ledger Sync Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null" | jq -r '.result.info | {state: .server_state, complete_ledgers, validated_ledger: .validated_ledger.seq, peers, load_factor, uptime: .uptime}'
	@echo ""
	@echo "Network ledger (mainnet):"
	@curl -s https://s1.ripple.com:51234 -X POST -H "Content-Type: application/json" -d '{"method":"ledger","params":[{"ledger_index":"validated"}]}' | jq -r '.result.ledger_index // "unavailable"'

logs: ## View rippled logs (follow mode)
	@echo "Following rippled logs (Ctrl+C to exit)..."
	@$(SSH_CMD) "docker logs -f rippled"

logs-tail: ## View last 100 lines of rippled logs
	@$(SSH_CMD) "docker logs --tail 100 rippled"

# Removed: health (duplicates sync-status)

peers: ## Show connected peers
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled peers" | jq -e '.result.peers[]? | {address, type, version}' || echo "No peer data available (rippled may still be starting)"

validators: ## Show validator list (UNL) status
	@echo "=== Validator List (UNL) Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled validators" \
		| jq '{status: .result.validator_list.status, expiration: .result.validator_list.expiration, publisher_sources: .result.validator_list.count, validators: (.result.trusted_validator_keys | length), quorum: .result.validation_quorum}'

validator-list-sites: ## Show UNL download status
	@echo "=== UNL Sites Download Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled validator_list_sites"

logs-startup: ## View first 200 lines of logs (startup)
	@$(SSH_CMD) "docker logs rippled 2>&1 | head -200"

consensus: ## Show consensus participation
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled consensus_info"

# Removed: ledger (duplicates sync-status)

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

# Removed: disk (duplicates resources command)

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

# Validator keys management (production)
build-validator-keys: ## Build validator-keys tool (one-time, 2-3 min)
	@./scripts/build-validator-keys-tool.sh

generate-keys: ## Generate production validator keys + token
	@./scripts/generate-validator-token.sh

deploy-keys: ## Deploy validator keys to server (automated)
	@./scripts/deploy-validator-keys.sh

rotate-keys: build-validator-keys generate-keys deploy-keys ## Complete key rotation workflow

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

# Consolidated key management commands
keys: ## Show validator keys (public key + seed)
	@echo "=== Validator Keys ==="
	@echo ""
	@echo "Public Key (from running validator):"
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null | jq -r '.result.info.pubkey_validator // \"Not validating (tracking mode)\"'"
	@echo ""
	@echo "Validation Seed (from config - ⚠️  PRIVATE!):"
	@$(SSH_CMD) "grep -A 1 '^\[validation_seed\]' /opt/rippled/rippled.cfg 2>/dev/null | tail -1 | xargs || echo 'No validation_seed in config'"
	@echo ""
	@echo "Use public key for UNL registration & DNS TXT record"
	@echo "⚠️  NEVER share the validation seed!"
	@echo ""

config: ## Show full rippled configuration
	@echo "=== rippled.cfg ==="
	@$(SSH_CMD) "cat /opt/rippled/rippled.cfg"

ledger-status: ## Show current and closed ledger
	@echo "=== Current Ledger ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled ledger current 2>/dev/null" \
		| jq '.result // {error: (.error_message // "Not synced yet")}' 2>/dev/null || echo "Not synced yet"
	@echo ""
	@echo "=== Closed Ledger ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled ledger closed 2>/dev/null" \
		| jq '.result // {error: (.error_message // "Not synced yet")}' 2>/dev/null || echo "Not synced yet"

wipe-ledger-db: ## Nuclear option: wipe database and resync
	@echo "⚠️  WARNING: This will DELETE all ledger data and resync from network!"
	@read -p "Type 'wipe' to confirm: " confirm && [ "$$confirm" = "wipe" ]
	@echo "Stopping and removing container..."
	@$(SSH_CMD) "cd /opt/rippled && docker-compose down"
	@echo "Removing database volume..."
	@$(SSH_CMD) "docker volume rm rippled_rippled-db 2>/dev/null || docker volume rm rippled-db 2>/dev/null || true"
	@echo "Starting rippled (will recreate volume)..."
	@$(SSH_CMD) "cd /opt/rippled && docker-compose up -d"
	@sleep 10
	@echo "✓ Database volume wiped - node will resync from network"
	@echo "Monitor with: make sync-status"

enable-validation: ## Enable validation (uncomment token, deploy, restart)
	@echo "Enabling validation..."
	@sed -i '' 's/^# # \[validator_token\]/[validator_token]/' docker/rippled.cfg
	@sed -i '' 's/^# eyJ/eyJ/' docker/rippled.cfg
	@sed -i '' 's/^# NjN/NjN/' docker/rippled.cfg
	@sed -i '' 's/^# Q2V/Q2V/' docker/rippled.cfg
	@sed -i '' 's/^# OVB/OVB/' docker/rippled.cfg
	@sed -i '' 's/^# R2R/R2R/' docker/rippled.cfg
	@sed -i '' 's/^# MHd/MHd/' docker/rippled.cfg
	@sed -i '' 's/^# eSI/eSI/' docker/rippled.cfg
	@sed -i '' 's/^# NUY/NUY/' docker/rippled.cfg
	@$(MAKE) update-config
	@$(MAKE) restart
	@sleep 30
	@echo "Checking validator status..."
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null" \
		| jq -r '.result.info | "State: \(.server_state)\nPublic Key: \(.pubkey_validator // "not validating")"'

disable-validation: ## Disable validation (comment token, deploy, restart)
	@echo "Disabling validation..."
	@sed -i '' 's/^\[validator_token\]/# # [validator_token]/' docker/rippled.cfg
	@sed -i '' 's/^eyJ/# eyJ/' docker/rippled.cfg
	@sed -i '' 's/^NjN/# NjN/' docker/rippled.cfg
	@sed -i '' 's/^Q2V/# Q2V/' docker/rippled.cfg
	@sed -i '' 's/^OVB/# OVB/' docker/rippled.cfg
	@sed -i '' 's/^R2R/# R2R/' docker/rippled.cfg
	@sed -i '' 's/^MHd/# MHd/' docker/rippled.cfg
	@sed -i '' 's/^eSI/# eSI/' docker/rippled.cfg
	@sed -i '' 's/^NUY/# NUY/' docker/rippled.cfg
	@$(MAKE) update-config
	@$(MAKE) restart
	@sleep 30
	@echo "Checking validator status..."
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null" \
		| jq -r '.result.info.server_state'

sync-debug: ## Comprehensive sync diagnostics (snapshot)
	@echo "=== Sync Snapshot ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info" \
		| jq '.result.info | {state:.server_state, complete:.complete_ledgers, peers:.peers, fetch_pack:.fetch_pack}'
	@echo ""
	@echo "=== Peer Ledger Comparison (top 20) ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled peers" \
		| jq -r '.result.peers[] | "\(.address)  \(.complete_ledgers)"' | head -n 20
	@echo ""
	@echo "=== Fetch Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled fetch_info" \
		| jq '.[].info | to_entries | .[:2]' || echo "Not fetching yet"

logs-sync: ## Follow sync-specific logs (live)
	@echo "Following sync logs (Ctrl+C to exit)..."
	@echo "Watching: InboundLedger, needed_state, Acquired, accepted ledger"
	@$(SSH_CMD) "docker exec rippled sh -lc 'tail -n +1 -f /var/log/rippled/debug.log | egrep -i \"(InboundLedger.*acquir|needed_state|got.*map|Acquired TX set|LedgerMaster.*set|accepted ledger)\"'"

peers-detail: ## Show peers with their ledger ranges
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled peers" \
		| jq -r '.result.peers[] | "\(.address)  \(.complete_ledgers)"'

fetch-status: ## Check fetch progress
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled fetch_info" \
		| jq '.[].info | to_entries | .[:2]' || echo "Not fetching yet"

health-check: ## Comprehensive validator health check
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║          Lucendex Validator - Health Check                     ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "=== Container Status ==="
	@$(SSH_CMD) "docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=rippled"
	@echo ""
	@echo "=== Sync Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled server_info 2>/dev/null" \
		| jq -r ".result.info | \"State: \(.server_state)\nLedgers: \(.complete_ledgers)\nPeers: \(.peers)\nUptime: \(.uptime)s\nLoad Factor: \(.load_factor)\nIO Latency: \(.io_latency_ms)ms\""
	@echo ""
	@echo "=== Validator List Status ==="
	@$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled validators 2>/dev/null" \
		| jq -r ".result.validator_list | \"Status: \(.status)\nExpiration: \(.expiration)\nPublisher Sources: \(.count)\"" && \
		$(SSH_CMD) "docker exec rippled /opt/ripple/bin/rippled validators 2>/dev/null" \
		| jq -r "\"Validators: \(.result.trusted_validator_keys | length)\nQuorum: \(.result.validation_quorum)\""
	@echo ""
	@echo "=== Resource Usage ==="
	@$(SSH_CMD) "df -h / | tail -1 | awk '{print \"Disk: \"\$$3\" used of \"\$$2\" (\"\$$5\")\"}'"
	@$(SSH_CMD) "free -h | grep Mem | awk '{print \"Memory: \"\$$3\" used of \"\$$2}'"
	@echo ""
	@echo "✓ Health check complete"

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
