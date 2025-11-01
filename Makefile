# Lucendex Unified Infrastructure CLI
# Single entry point for all infrastructure operations

.PHONY: help deploy status destroy validator data-services backend test

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help:
	@echo "$(BLUE)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║        Lucendex Infrastructure CLI                        ║$(NC)"
	@echo "$(BLUE)║        Neutral, Non-Custodial XRPL DEX Aggregator         ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)Global Commands:$(NC)"
	@echo "  make deploy            - Deploy all infrastructure"
	@echo "  make status            - Check status of all components"
	@echo "  make sync-status       - Check sync status of ALL rippled nodes"
	@echo "  make logs-tail         - View recent logs from ALL nodes (last 30 lines)"
	@echo "  make resources         - Check resources of ALL infrastructure"
	@echo "  make destroy           - Destroy all infrastructure"
	@echo "  make test              - Run all backend tests"
	@echo ""
	@echo "$(GREEN)Component Commands:$(NC)"
	@echo "  make validator-*       - Validator operations (M4)"
	@echo "  make data-*            - Data services operations (M0)"
	@echo "  make backend-*         - Backend operations"
	@echo ""
	@echo "$(YELLOW)Validator Commands:$(NC)"
	@echo "  make validator-deploy  - Deploy validator"
	@echo "  make validator-status  - Check validator status"
	@echo "  make validator-logs    - View validator logs"
	@echo "  make validator-sync    - Check sync status"
	@echo "  make validator-backup  - Create backup"
	@echo "  make validator-destroy - Destroy validator (with backups)"
	@echo "  make validator-ssh     - SSH into validator"
	@echo ""
	@echo "$(YELLOW)Data Services Commands:$(NC)"
	@echo "  make data-deploy               - Deploy data services"
	@echo "  make data-status               - Check services status"
	@echo "  make data-logs                 - View all service logs (follow mode)"
	@echo "  make data-logs-tail            - View last 100 lines"
	@echo "  make data-sync-status-api      - Check API node sync"
	@echo "  make data-sync-status-history  - Check history node sync"
	@echo "  make data-backup               - Create database backup"
	@echo "  make data-db-shell             - Open PostgreSQL shell"
	@echo "  make data-ssh                  - SSH into data services VM"
	@echo "  make data-health-check         - Comprehensive health check"
	@echo "  make data-validators-api       - Check API UNL status"
	@echo "  make data-peers-api            - Check API peers"
	@echo "  make data-db-health            - Database health check"
	@echo "  make data-disk-space           - Check disk usage"
	@echo "  make data-network-test         - Test network connectivity"
	@echo "  make rotate-passwords          - Rotate all DB passwords (zero downtime)"
	@echo ""
	@echo "$(YELLOW)Indexer Commands:$(NC)"
	@echo "  make indexer-deploy    - Build and deploy indexer"
	@echo "  make indexer-status    - Check indexer status"
	@echo "  make indexer-logs      - View indexer logs"
	@echo "  make indexer-restart   - Restart indexer service"
	@echo ""
	@echo "$(YELLOW)Backend Commands:$(NC)"
	@echo "  make backend-test      - Run all tests"
	@echo "  make backend-cover     - Run tests with coverage"
	@echo "  make backend-build     - Build indexer binary"
	@echo "  make backend-deploy    - Build and deploy indexer"
	@echo ""

# Global Operations
deploy:
	@echo "$(GREEN)Deploying all infrastructure...$(NC)"
	@cd infra && ./deploy.sh all

status:
	@echo "$(GREEN)=== Infrastructure Status ===$(NC)"
	@cd infra && ./deploy.sh status

destroy:
	@echo "$(YELLOW)WARNING: This will destroy ALL infrastructure!$(NC)"
	@cd infra && ./deploy.sh destroy

sync-status:
	@echo "$(BLUE)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          Lucendex Sync Status - All Nodes                 ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Validator (Amsterdam) ===$(NC)"
	@cd infra/validator && make sync-status || echo "Validator not deployed"
	@echo ""
	@echo "$(YELLOW)=== Data Services - API Node ===$(NC)"
	@cd infra/data-services && make sync-status-api || echo "API node not deployed"
	@echo ""
	@echo "$(YELLOW)=== Data Services - History Node ===$(NC)"
	@cd infra/data-services && make sync-status-history || echo "History node not deployed"

resources:
	@echo "$(BLUE)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          Lucendex Resources - All Infrastructure          ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Validator VM (Amsterdam) ===$(NC)"
	@cd infra/validator && make resources || echo "Validator not deployed"
	@echo ""
	@echo "$(YELLOW)=== Data Services VM ===$(NC)"
	@cd infra/data-services && make resources || echo "Data services not deployed"

logs-tail:
	@echo "$(BLUE)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          Recent Logs from All Nodes (last 30 lines)      ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Validator (last 30 lines) ===$(NC)"
	@cd infra/validator && ssh -i terraform/validator_ssh_key root@$$(cd terraform && terraform output -raw validator_ip 2>/dev/null) "docker logs --tail=30 rippled 2>&1" || echo "Validator not deployed"
	@echo ""
	@echo "$(YELLOW)=== API Node (last 30 lines) ===$(NC)"
	@cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) "docker logs --tail=30 lucendex-rippled-api 2>&1" || echo "API node not deployed"
	@echo ""
	@echo "$(YELLOW)=== History Node (last 30 lines) ===$(NC)"
	@cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) "docker logs --tail=30 lucendex-rippled-history 2>&1" || echo "History node not deployed"

test:
	@echo "$(GREEN)Running all backend tests...$(NC)"
	@cd backend && go test ./... -v -cover

# Validator Operations (delegate to infra/validator/Makefile)
validator-deploy:
	@cd infra/validator && make deploy

validator-status:
	@cd infra/validator && make status

validator-logs:
	@cd infra/validator && make logs

validator-logs-tail:
	@cd infra/validator && make logs-tail

validator-sync:
	@cd infra/validator && make sync-status

validator-backup:
	@cd infra/validator && make backup

validator-ssh:
	@cd infra/validator && make ssh

validator-resources:
	@cd infra/validator && make resources

validator-destroy:
	@cd infra/validator && make destroy

validator-build-keys:
	@cd infra/validator && make build-validator-keys

validator-generate-keys:
	@cd infra/validator && make generate-keys

validator-deploy-keys:
	@cd infra/validator && make deploy-keys

validator-rotate-keys:
	@cd infra/validator && make rotate-keys

# Data Services Operations (delegate to infra/data-services/Makefile)
data-deploy:
	@cd infra/data-services && make deploy

data-status:
	@cd infra/data-services && make status

data-logs:
	@cd infra/data-services && make logs

data-sync-status-api:
	@cd infra/data-services && make sync-status-api

data-sync-status-history:
	@cd infra/data-services && make sync-status-history

data-backup:
	@cd infra/data-services && make backup

data-db-shell:
	@cd infra/data-services && make db-shell

data-services:
	@cd infra/data-services && make services

data-ssh:
	@cd infra/data-services && make ssh

data-resources:
	@cd infra/data-services && make resources

data-stop:
	@cd infra/data-services && make stop

data-start:
	@cd infra/data-services && make start

data-restart:
	@cd infra/data-services && make restart

# Indexer Operations
indexer-deploy:
	@cd infra/data-services && make indexer-deploy

indexer-status:
	@cd infra/data-services && make indexer-status

indexer-logs:
	@cd infra/data-services && make indexer-logs

indexer-restart:
	@cd infra/data-services && make indexer-restart

# Security Operations
rotate-passwords:
	@cd infra/data-services && make rotate-passwords

# Configuration Viewing
data-config:
	@cd infra/data-services && make config

data-config-api:
	@cd infra/data-services && make config-api

data-config-history:
	@cd infra/data-services && make config-history

data-config-postgres:
	@cd infra/data-services && make config-postgres

data-update-config-api:
	@cd infra/data-services && make update-config-api

data-update-config-history:
	@cd infra/data-services && make update-config-history

data-update-config-postgres:
	@cd infra/data-services && make update-config-postgres

data-update-validators:
	@cd infra/data-services && make update-validators

data-destroy:
	@cd infra/data-services && make destroy

data-logs-tail:
	@cd infra/data-services && make logs-tail

data-logs-api:
	@cd infra/data-services && make logs-api

data-logs-history:
	@cd infra/data-services && make logs-history

data-logs-postgres:
	@cd infra/data-services && make logs-postgres

data-logs-errors:
	@cd infra/data-services && make logs-errors

data-health-check:
	@cd infra/data-services && make health-check

data-validators-api:
	@cd infra/data-services && make validators-api

data-validators-history:
	@cd infra/data-services && make validators-history

data-peers-api:
	@cd infra/data-services && make peers-api

data-peers-history:
	@cd infra/data-services && make peers-history

data-db-health:
	@cd infra/data-services && make db-health

data-disk-space:
	@cd infra/data-services && make disk-space

data-network-test:
	@cd infra/data-services && make network-test

validator-config:
	@cd infra/validator && make config

validator-peers:
	@cd infra/validator && make peers

validator-validators:
	@cd infra/validator && make validators

validator-consensus:
	@cd infra/validator && make consensus

validator-restart:
	@cd infra/validator && make restart

validator-stop:
	@cd infra/validator && make stop

validator-start:
	@cd infra/validator && make start

validator-keys:
	@cd infra/validator && make keys

validator-logs-startup:
	@cd infra/validator && docker logs rippled 2>&1 | head -200

data-logs-startup-api:
	@cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) "docker logs lucendex-rippled-api 2>&1 | head -200"

data-logs-startup-history:
	@cd infra/data-services && ssh -i terraform/data_services_ssh_key root@$$(cd terraform && terraform output -raw data_services_ip) "docker logs lucendex-rippled-history 2>&1 | head -200"

# Backend Operations
backend-test:
	@echo "$(GREEN)Running backend tests...$(NC)"
	@cd backend && go test ./... -v

backend-cover:
	@echo "$(GREEN)Running backend tests with coverage...$(NC)"
	@cd backend && go test ./... -v -cover
	@cd backend && go test ./... -coverprofile=coverage.out
	@cd backend && go tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)✓ Coverage report: backend/coverage.html$(NC)"

backend-build:
	@echo "$(GREEN)Building indexer binary...$(NC)"
	@cd backend && go build -o indexer ./cmd/indexer
	@echo "$(GREEN)✓ Binary: backend/indexer$(NC)"

backend-deploy:
	@echo "$(GREEN)Building and deploying indexer...$(NC)"
	@cd backend && go build -o indexer ./cmd/indexer
	@echo "$(YELLOW)Copy to data-services VM:$(NC)"
	@echo "  scp -i infra/data-services/terraform/data_services_ssh_key backend/indexer root@\$$(cd infra/data-services/terraform && terraform output -raw data_services_ip):/opt/lucendex/"
	@echo "$(YELLOW)Run on VM:$(NC)"
	@echo "  export DATABASE_URL='postgres://indexer_rw:<password>@localhost:5432/lucendex'"
	@echo "  export RIPPLED_WS='ws://localhost:6006'"
	@echo "  ./indexer"

# Shortcuts
v-deploy: validator-deploy
v-status: validator-status
v-logs: validator-logs
v-logs-tail:
	@cd infra/validator && make logs-tail
v-sync: validator-sync

d-deploy: data-deploy
d-status: data-status
d-logs: data-logs
d-logs-tail:
	@cd infra/data-services && make logs-tail
d-sync-api: data-sync-status-api
d-sync-history: data-sync-status-history

b-test: backend-test
b-build: backend-build
