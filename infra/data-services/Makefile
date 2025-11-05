# Makefile for Lucendex Data Services Management
# Provides commands for deployment, monitoring, and maintenance

.PHONY: help deploy destroy status logs ssh backup db-shell services restart indexer-deploy indexer-status indexer-logs rotate-passwords config-api config-history config-postgres

# Default target
help:
	@echo "Lucendex Data Services Management"
	@echo ""
	@echo "Core Operations:"
	@echo "  make deploy                - Deploy data services infrastructure"
	@echo "  make continue-deploy       - Continue interrupted deployment (fixes SSH + deploys services)"
	@echo "  make destroy               - Destroy data services infrastructure"
	@echo "  make status                - Show status of all services"
	@echo "  make version               - Show service versions"
	@echo "  make services              - List running Docker containers"
	@echo "  make restart               - Restart all services"
	@echo "  make start                 - Start all services"
	@echo "  make stop                  - Stop all services"
	@echo "  make ssh                   - SSH into data services VM"
	@echo ""
	@echo "Monitoring & Health:"
	@echo "  make health-check          - Comprehensive health check"
	@echo "  make sync-status-api       - Check API node sync status"
	@echo "  make sync-status-history   - Check history node sync status"
	@echo "  make watch-sync-api        - Watch API node sync (10min, detect stalls)"
	@echo "  make watch-sync-history    - Watch history node sync (10min, detect stalls)"
	@echo "  make sync-debug-api        - API node sync diagnostics (detailed)"
	@echo "  make sync-debug-history    - History node sync diagnostics (detailed)"
	@echo "  make validators-api        - Check API node UNL status"
	@echo "  make validators-history    - Check history node UNL status"
	@echo "  make validator-list-sites-api    - API UNL download status"
	@echo "  make validator-list-sites-history - History UNL download status"
	@echo "  make peers-api             - Show API node peers"
	@echo "  make peers-history         - Show history node peers"
	@echo "  make resources             - Show CPU and memory usage"
	@echo "  make disk-space            - Check disk usage"
	@echo "  make network-test          - Test network connectivity"
	@echo ""
	@echo "Logs:"
	@echo "  make logs                  - Follow all service logs"
	@echo "  make logs-tail             - Last 100 lines (all services)"
	@echo "  make logs-api              - API node logs"
	@echo "  make logs-history          - History node logs"
	@echo "  make logs-postgres         - PostgreSQL logs"
	@echo "  make logs-errors           - Recent errors (all services)"
	@echo ""
	@echo "Database:"
	@echo "  make db-shell              - Open PostgreSQL shell"
	@echo "  make db-health             - Database health check"
	@echo "  make backup                - Create database backup"
	@echo "  make rotate-passwords      - Rotate DB passwords"
	@echo ""
	@echo "Configuration:"
	@echo "  make config                - Show all configurations"
	@echo "  make config-api            - Show API node config"
	@echo "  make config-history        - Show history node config"
	@echo "  make config-postgres       - Show PostgreSQL config"
	@echo "  make update-config-api     - Upload API node config"
	@echo "  make update-config-history - Upload history node config"
	@echo "  make update-config-postgres - Upload PostgreSQL config"
	@echo "  make update-validators     - Upload validators.txt"
	@echo ""
	@echo "Indexer:"
	@echo "  make indexer-deploy        - Build and deploy indexer"
	@echo "  make indexer-status        - Check indexer status"
	@echo "  make indexer-logs          - Follow indexer logs"
	@echo "  make indexer-restart       - Restart indexer"
	@echo ""
	@echo "⚠️  Admin (Destructive - Requires cd infra/data-services/):"
	@echo "  make wipe-ledger-db-api    - Wipe API node database"
	@echo "  make wipe-ledger-db-history - Wipe history node database"
	@echo "  make wipe-ledger-db-all    - Wipe all ledger databases"

# Deploy infrastructure and services
deploy:
	@echo "Deploying data services..."
	@chmod +x data-services-deploy.sh
	@./data-services-deploy.sh

# Continue interrupted deployment (fixes SSH + deploys services)
continue-deploy:
	@echo "=== Continuing Data Services Deployment ==="
	@echo "Step 1: Uploading and running setup script..."
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no scripts/setup-vm.sh root@$$(cd terraform && terraform output -raw data_services_ip):/root/
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) 'bash /root/setup-vm.sh'
	@echo ""
	@echo "Step 2: Uploading Docker configs..."
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/docker-compose.yml root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/rippled-api.cfg root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/rippled-history.cfg root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/postgresql.conf root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/validators.txt root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@scp -i terraform/data_services_ssh_key -o StrictHostKeyChecking=no docker/init-db.sql root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@echo ""
	@echo "Step 3: Creating .env file..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'cd /opt/lucendex/docker && [ ! -f .env ] && echo "POSTGRES_PASSWORD=$$(openssl rand -base64 32)" > .env && echo "INDEXER_DB_PASSWORD=$$(openssl rand -base64 32)" >> .env || echo ".env exists, skipping"'
	@echo ""
	@echo "Step 4: Starting services..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'cd /opt/lucendex/docker && docker compose up -d'
	@echo ""
	@echo "✓ Deployment continued successfully!"
	@echo "Check status with: make health-check"

# Destroy infrastructure
destroy:
	@chmod +x data-services-destroy.sh
	@./data-services-destroy.sh

# Show service status
status:
	@echo "=== Data Services Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose ps"

# Show versions
version: ## Show service versions
	@echo "=== Service Versions ==="
	@echo "rippled API:"
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-rippled-api /opt/ripple/bin/rippled --version"
	@echo ""
	@echo "rippled History:"
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-rippled-history /opt/ripple/bin/rippled --version"
	@echo ""
	@echo "PostgreSQL:"
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-postgres psql --version"

# Tail logs (follow mode)
logs:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose logs -f --tail=100"

# View last 100 lines without following
logs-tail:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose logs --tail=100"

# Show PostgreSQL logs (for debugging)
logs-postgres:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker logs lucendex-postgres 2>&1 | tail -100"

# SSH into VM
ssh:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip)

# Create database backup
backup:
	@echo "Creating database backup..."
	@mkdir -p backups
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-postgres pg_dump -U postgres lucendex" > backups/lucendex_$$(date +%Y%m%d_%H%M%S).sql
	@echo "✓ Backup created in backups/"

# Open PostgreSQL shell
db-shell:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec -it lucendex-postgres psql -U postgres -d lucendex"

# List running services
services:
	@echo "=== Running Services ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Stop all services
stop:
	@echo "Stopping all services..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose down"
	@echo "✓ Services stopped"

# Start all services
start:
	@echo "Starting all services..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose up -d"
	@echo "✓ Services started"

# Restart all services (soft restart, doesn't remount volumes)
restart:
	@echo "Restarting all services..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cd /opt/lucendex/docker && docker compose restart"
	@echo "✓ Services restarted"

# Check rippled API sync status
sync-status-api:
	@echo "=== rippled API Sync Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled server_info | jq "{state: .result.info.server_state, ledgers: .result.info.complete_ledgers, peers: .result.info.peers, uptime: .result.info.uptime}"'

# Check rippled history sync status
sync-status-history:
	@echo "=== rippled Full-History Sync Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled server_info | jq "{state: .result.info.server_state, ledgers: .result.info.complete_ledgers, peers: .result.info.peers, uptime: .result.info.uptime}"'

# Watch API node sync for stalls
watch-sync-api:
	@echo "=== Watching API Node Sync (10min, stall threshold: 180s) ==="
	@scp -i terraform/data_services_ssh_key scripts/stall_detector.sh root@$$(cd terraform && terraform output -raw data_services_ip):/tmp/
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'CONTAINER=lucendex-rippled-api PORT=51234 bash /tmp/stall_detector.sh'

# Watch history node sync for stalls
watch-sync-history:
	@echo "=== Watching History Node Sync (10min, stall threshold: 180s) ==="
	@scp -i terraform/data_services_ssh_key scripts/stall_detector.sh root@$$(cd terraform && terraform output -raw data_services_ip):/tmp/
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'CONTAINER=lucendex-rippled-history PORT=51237 bash /tmp/stall_detector.sh'

# Show resource usage
resources:
	@echo "=== Resource Usage ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"echo '--- System ---' && free -h && echo '' && df -h / && echo '' && echo '--- Docker ---' && docker stats --no-stream"

# Deploy indexer binary and systemd service
indexer-deploy:
	@echo "Building indexer binary..."
	@cd ../../backend && go build -o indexer ./cmd/indexer
	@echo "Copying indexer to VM..."
	@scp -i terraform/data_services_ssh_key ../../backend/indexer root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/
	@echo "Copying systemd service..."
	@scp -i terraform/data_services_ssh_key docker/indexer.service root@$$(cd terraform && terraform output -raw data_services_ip):/etc/systemd/system/
	@echo "Enabling and starting indexer..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"systemctl daemon-reload && systemctl enable indexer && systemctl start indexer"
	@echo "✓ Indexer deployed and running"

# Check indexer status
indexer-status:
	@echo "=== Indexer Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"systemctl status indexer --no-pager"

# View indexer logs
indexer-logs:
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"tail -f /opt/lucendex/logs/indexer.log"

# Restart indexer
indexer-restart:
	@echo "Restarting indexer..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"systemctl restart indexer"
	@echo "✓ Indexer restarted"

# Rotate database passwords
rotate-passwords:
	@echo "Rotating database passwords..."
	@chmod +x scripts/rotate-passwords.sh
	@./scripts/rotate-passwords.sh \
		$$(cd terraform && terraform output -raw data_services_ip) \
		terraform/data_services_ssh_key \
		terraform/.envrc

# Show rippled API configuration
config-api:
	@echo "=== rippled API Configuration ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cat /opt/lucendex/docker/rippled-api.cfg"

# Show rippled History configuration
config-history:
	@echo "=== rippled Full-History Configuration ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cat /opt/lucendex/docker/rippled-history.cfg"

# Show PostgreSQL configuration
config-postgres:
	@echo "=== PostgreSQL Configuration ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"cat /opt/lucendex/docker/postgresql.conf"

# Show all configurations
config: config-api config-history config-postgres
	@echo ""
	@echo "✓ All configurations displayed above"

# Update rippled API configuration
update-config-api:
	@echo "Uploading rippled API configuration..."
	@scp -i terraform/data_services_ssh_key docker/rippled-api.cfg root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@echo "✓ Configuration uploaded. Restart required: make restart"

# Update rippled History configuration
update-config-history:
	@echo "Uploading rippled History configuration..."
	@scp -i terraform/data_services_ssh_key docker/rippled-history.cfg root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@echo "✓ Configuration uploaded. Restart required: make restart"

# Update PostgreSQL configuration
update-config-postgres:
	@echo "Uploading PostgreSQL configuration..."
	@scp -i terraform/data_services_ssh_key docker/postgresql.conf root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@echo "✓ Configuration uploaded. Restart required: make restart"

# Update validators.txt
update-validators:
	@echo "Uploading validators.txt..."
	@scp -i terraform/data_services_ssh_key docker/validators.txt root@$$(cd terraform && terraform output -raw data_services_ip):/opt/lucendex/docker/
	@echo "✓ Validators list uploaded. Restart required: make restart"

# Database Management (Admin - Destructive)
wipe-ledger-db-api: ## Nuclear: wipe API node database and resync
	@echo "⚠️  WARNING: This will DELETE all API node ledger data!"
	@read -p "Type 'wipe' to confirm: " confirm && [ "$$confirm" = "wipe" ]
	@echo "Cleaning API node database..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-rippled-api sh -c 'rm -f /var/lib/rippled/db/state* && rm -rf /var/lib/rippled/db/rocksdb/* /var/lib/rippled/db/nudb/*'"
	@echo "Restarting API node..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker restart lucendex-rippled-api"
	@sleep 5
	@echo "✓ API node database wiped - will resync from network"
	@echo "Monitor with: make sync-status-api"

wipe-ledger-db-history: ## Nuclear: wipe history node database and resync
	@echo "⚠️  WARNING: This will DELETE all history node ledger data!"
	@read -p "Type 'wipe' to confirm: " confirm && [ "$$confirm" = "wipe" ]
	@echo "Cleaning history node database..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-rippled-history sh -c 'rm -f /var/lib/rippled/db/state* && rm -rf /var/lib/rippled/db/rocksdb/* /var/lib/rippled/db/nudb/*'"
	@echo "Restarting history node..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker restart lucendex-rippled-history"
	@sleep 5
	@echo "✓ History node database wiped - will resync from network"
	@echo "Monitor with: make sync-status-history"

wipe-ledger-db-all: ## Nuclear: wipe ALL node databases and resync
	@echo "⚠️  WARNING: This will DELETE ALL ledger data (API + History nodes)!"
	@read -p "Type 'wipe' to confirm: " confirm && [ "$$confirm" = "wipe" ]
	@echo "Cleaning all node databases..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker exec lucendex-rippled-api sh -c 'rm -f /var/lib/rippled/db/state* && rm -rf /var/lib/rippled/db/rocksdb/* /var/lib/rippled/db/nudb/*' && docker exec lucendex-rippled-history sh -c 'rm -f /var/lib/rippled/db/state* && rm -rf /var/lib/rippled/db/rocksdb/* /var/lib/rippled/db/nudb/*'"
	@echo "Restarting all nodes..."
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker restart lucendex-rippled-api lucendex-rippled-history"
	@sleep 10
	@echo "✓ All databases wiped - nodes will resync from network"
	@echo "Monitor with: make health-check"

# Sync Diagnostics
sync-debug-api: ## Comprehensive API node sync diagnostics
	@echo "=== API Node Sync Debug ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled server_info | jq "{state: .result.info.server_state, complete: .result.info.complete_ledgers, peers: .result.info.peers, fetch_pack: .result.info.fetch_pack}"'
	@echo ""
	@echo "=== Peer Ledger Comparison (API) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled peers 2>/dev/null | jq -r "if .result.peers then (.result.peers[] | \"\(.address)  \(.complete_ledgers)\") else \"No peers data available\" end" | head -20' || echo "Peers query failed"
	@echo ""
	@echo "=== Fetch Status (API) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled fetch_info 2>/dev/null | jq -r "if type == \"object\" and .result then .result else \"Not fetching yet\" end"' || echo "Not fetching yet"

sync-debug-history: ## Comprehensive history node sync diagnostics
	@echo "=== History Node Sync Debug ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled server_info | jq "{state: .result.info.server_state, complete: .result.info.complete_ledgers, peers: .result.info.peers, fetch_pack: .result.info.fetch_pack}"'
	@echo ""
	@echo "=== Peer Ledger Comparison (History) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled peers 2>/dev/null | jq -r "if .result.peers then (.result.peers[] | \"\(.address)  \(.complete_ledgers)\") else \"No peers data available\" end" | head -20' || echo "Peers query failed"
	@echo ""
	@echo "=== Fetch Status (History) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled fetch_info 2>/dev/null | jq -r "if type == \"object\" and .result then .result else \"Not fetching yet\" end"' || echo "Not fetching yet"

# Production Diagnostics
validators-api:
	@echo "=== API Node Validators Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled validators 2>/dev/null | jq "{status: .result.validator_list.status, expiration: .result.validator_list.expiration, publisher_sources: .result.validator_list.count, validators: (.result.trusted_validator_keys | length), quorum: .result.validation_quorum}"' || echo "Command failed or node not ready"

validators-history:
	@echo "=== History Node Validators Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled validators 2>/dev/null | jq "{status: .result.validator_list.status, expiration: .result.validator_list.expiration, publisher_sources: .result.validator_list.count, validators: (.result.trusted_validator_keys | length), quorum: .result.validation_quorum}"' || echo "Command failed or node not ready"

validator-list-sites-api:
	@echo "=== API Node UNL Sites Download Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled validator_list_sites 2>/dev/null' || echo "Command not available or node not ready"

validator-list-sites-history:
	@echo "=== History Node UNL Sites Download Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled validator_list_sites 2>/dev/null' || echo "Command not available or node not ready"

peers-api:
	@echo "=== API Node Peers ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled peers 2>/dev/null | jq "if .result.peers then {peer_count: (.result.peers | length), peers: [.result.peers[] | {address, version, uptime}]} else \"No peers data available\" end"' || echo "Peers query failed"

peers-history:
	@echo "=== History Node Peers ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled peers 2>/dev/null | jq "if .result.peers then {peer_count: (.result.peers | length), peers: [.result.peers[] | {address, version, uptime}]} else \"No peers data available\" end"' || echo "Peers query failed"

db-health:
	@echo "=== Database Health Check ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-postgres psql -U postgres -d lucendex -c "SELECT version();" && echo "" && docker exec lucendex-postgres psql -U postgres -d lucendex -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'"'"'.'"'"'||tablename)) AS size FROM pg_tables WHERE schemaname = '"'"'public'"'"' ORDER BY pg_total_relation_size(schemaname||'"'"'.'"'"'||tablename) DESC;"'

disk-space:
	@echo "=== Disk Space Check ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"df -h / && echo '' && echo '=== API Node DB ===' && du -sh /var/lib/rippled/api/db/ 2>/dev/null || echo 'Not found' && echo '' && echo '=== History Node DB ===' && du -sh /var/lib/rippled/history/db/ 2>/dev/null || echo 'Not found'"

network-test:
	@echo "=== Network Connectivity Test ==="
	@echo "Testing API node RPC (port 51234)..."
	@curl -s --max-time 5 http://$$(cd terraform && terraform output -raw data_services_ip):51234 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' | jq '.result.info.server_state' || echo "❌ API RPC not reachable"
	@echo ""
	@echo "Testing peer ports..."
	@nc -zv $$(cd terraform && terraform output -raw data_services_ip) 51235 2>&1 | grep -q succeeded && echo "✓ API peer port 51235 open" || echo "❌ API peer port 51235 closed"
	@nc -zv $$(cd terraform && terraform output -raw data_services_ip) 51236 2>&1 | grep -q succeeded && echo "✓ History peer port 51236 open" || echo "❌ History peer port 51236 closed"

health-check:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║          Lucendex Data Services - Health Check                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "=== Container Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=lucendex"
	@echo ""
	@echo "=== API Node Sync ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled server_info 2>/dev/null | jq -r ".result.info | \"State: \(.server_state)\nLedgers: \(.complete_ledgers)\nPeers: \(.peers)\nUptime: \(.uptime)s\""'
	@echo ""
	@echo "=== History Node Sync ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-history rippled server_info 2>/dev/null | jq -r ".result.info | \"State: \(.server_state)\nLedgers: \(.complete_ledgers)\nPeers: \(.peers)\nUptime: \(.uptime)s\""'
	@echo ""
	@echo "=== Validator List Status ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-rippled-api rippled validators 2>/dev/null | jq -r ".result.validator_list | \"Status: \(.status)\nExpiration: \(.expiration)\nCount: \(.count)\""'
	@echo ""
	@echo "=== Database ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker exec lucendex-postgres psql -U postgres -d lucendex -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = '"'"'public'"'"';" 2>/dev/null | xargs -I{} echo "Tables: {}"'
	@echo ""
	@echo "=== Disk Usage ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"df -h / | tail -1 | awk '{print \"Root: \"\$$3\" used of \"\$$2\" (\"\$$5\")\"}'"
	@echo ""
	@echo "✓ Health check complete"

logs-api:
	@echo "=== API Node Logs (last 50 lines) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker logs --tail 50 lucendex-rippled-api 2>&1"

logs-history:
	@echo "=== History Node Logs (last 50 lines) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		"docker logs --tail 50 lucendex-rippled-history 2>&1"

logs-errors:
	@echo "=== Recent Errors (all services) ==="
	@ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) \
		'docker logs lucendex-rippled-api 2>&1 | grep -i error | tail -20 && echo "" && docker logs lucendex-rippled-history 2>&1 | grep -i error | tail -20 && echo "" && docker logs lucendex-postgres 2>&1 | grep -i error | tail -20'
