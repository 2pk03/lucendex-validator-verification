.PHONY: deploy help

help:
	@echo "LucenDEX Website Deployment"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy          Push website to public repo → Cloudflare Pages"
	@echo "  update-toml     Update validator xrp-ledger.toml only"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy            # Deploy full website"
	@echo "  make update-toml       # Update validator verification only"

deploy:
	@echo "Deploying website to lucendex.com..."
	@./website-deploy.sh

update-toml:
	@echo "Updating validator xrp-ledger.toml..."
	@cd ../validator && ./validator-attestation.sh
