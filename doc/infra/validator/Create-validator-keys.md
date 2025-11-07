# Production Validator Key Generation

**CRITICAL**: This is the ONLY secure method for generating XRPL validator keys for production use.

## Overview

This guide covers generating secure validator keys using the official `validator-keys` tool. This approach:

- ✅ Uses `validator_token` in rippled.cfg (production-secure)
- ✅ Master key stays offline (never on server)
- ✅ Approved by XRPL Foundation
- ✅ Enables key rotation without downtime
- ❌ Does NOT use `validation_seed` (less secure)

## Prerequisites

- macOS M1/M2 Mac (or any Docker-capable system)
- Docker installed and running
- SSH access to validator server
- GitHub access for domain verification repo

## Complete Workflow

### Step 1: Build validator-keys Tool

The `validator-keys` tool must be built from source. We use Docker for reproducible builds:

```bash
cd infra/validator/scripts
./build-validator-keys-tool.sh
```

**What this does:**
- Builds validator-keys in Docker (linux/amd64)
- Extracts binary to `~/.local/bin/validator-keys`
- Verifies binary works (runs under Rosetta on M1)
- Takes 10-15 minutes first time (downloads and compiles dependencies)

**Dockerfile location:** `infra/validator/docker/Dockerfile.validator-keys`

### Step 2: Generate Validator Token

Generate secure keys and optionally deploy automatically:

```bash
cd infra/validator/scripts
./generate-validator-token.sh
```

**What this does:**
1. Generates master keys → `~/.validator-keys-secure/validator-keys.json`
2. Generates validator_token from master keys
3. Creates rippled.cfg snippet
4. Creates xrp-ledger.toml for domain verification
5. Optionally deploys automatically:
   - Updates rippled.cfg with `[validator_token]`
   - Updates xrp-ledger.toml with new public key
   - Stops validator
   - Uploads new config
   - Starts validator
   - Pushes TOML to GitHub (Cloudflare auto-deploys)

**Generated files in `~/.validator-keys-secure/`:**
```
validator-keys.json              # Master key (OFFLINE BACKUP ONLY!)
rippled-validator-config.txt     # Snippet for rippled.cfg
xrp-ledger.toml                  # Domain verification file
public_key.txt                   # Public key (safe to share)
```

## Security Model

### Master Key (validator-keys.json)

**CRITICAL SECURITY:**
- ⚠️  **NEVER** put on validator server
- ⚠️  **NEVER** commit to git
- ✅ Backup to encrypted USB + password manager
- ✅ Only needed for key rotation
- ✅ Can regenerate validator_token anytime

### Validator Token

**SAFE FOR SERVER:**
- ✅ Put in rippled.cfg `[validator_token]` section
- ✅ Cannot be used to derive master key
- ✅ Rotatable without changing public key
- ✅ Industry-standard security model

### Public Key

**SAFE TO PUBLISH:**
- ✅ Share publicly
- ✅ Use for UNL registration
- ✅ Use in domain verification
- ✅ Publish in xrp-ledger.toml

## File Structure

```
infra/validator/
├── docker/
│   ├── Dockerfile.validator-keys    # Builds validator-keys tool
│   └── rippled.cfg                   # Validator config (add token here)
├── scripts/
│   ├── build-validator-keys-tool.sh # Step 1: Build tool
│   └── generate-validator-token.sh  # Step 2: Generate keys & deploy
└── lucendex-validator-verification/
    └── .well-known/
        └── xrp-ledger.toml          # Domain verification (auto-updated)
```

## Manual Deployment (Alternative)

If you skip automated deployment, deploy manually:

```bash
cd infra/validator

# 1. Update rippled.cfg
# Add content from ~/.validator-keys-secure/rippled-validator-config.txt

# 2. Deploy
make stop
make update-config
make start

# 3. Verify
make sync-status  # Should show 'proposing'
make logs-tail    # Check for validation messages

# 4. Update domain verification
cp ~/.validator-keys-secure/xrp-ledger.toml \
   lucendex-validator-verification/.well-known/

# 5. Push to GitHub
cd lucendex-validator-verification
git add .well-known/xrp-ledger.toml
git commit -m "security: update validator public key"
git push  # Cloudflare auto-deploys
```

## Key Rotation

To rotate keys (without changing public key):

```bash
cd ~/.validator-keys-secure

# Generate new token from existing master key
~/.local/bin/validator-keys create_token --keyfile validator-keys.json

# Deploy new token (same process as initial setup)
# Public key remains unchanged!
```

## Troubleshooting

### Build Fails

```bash
# Check Docker is running
docker ps

# Rebuild from scratch
docker rmi validator-keys-builder:latest
./build-validator-keys-tool.sh
```

### Binary Won't Run on M1

The binary is x86_64 and runs under Rosetta. Ensure Rosetta is installed:

```bash
softwareupdate --install-rosetta
```

### Validator Not Validating

```bash
cd infra/validator

# Check status
make sync-status

# Should show:
# - server_state: proposing
# - pubkey_validator: <your public key>

# Check logs
make logs-tail

# Look for validation messages
```

### Domain Verification Not Working

```bash
# Check TOML is accessible
curl https://lucendex.com/.well-known/xrp-ledger.toml

# Check GitHub push succeeded
cd lucendex-validator-verification
git log -1

# Wait 30-60s for Cloudflare deployment
```

## Security Incident Response

If `validator-keys.json` is compromised:

1. **Immediately** generate new keys
2. Deploy new validator_token
3. Update domain verification with new public key
4. Notify network operators (if in UNL)
5. Document incident

## References

- [XRPL Validator Guide](https://xrpl.org/run-rippled-as-a-validator.html)
- [validator-keys Tool](https://github.com/ripple/validator-keys-tool)
- [Validator Keys Guide](https://github.com/ripple/validator-keys-tool/blob/master/doc/validator-keys-tool-guide.md)

## Support

For issues:
1. Check logs: `make logs-tail`
2. Check status: `make sync-status`
3. Review this documentation
4. Check XRPL documentation

---

**Last Updated:** 2025-11-01
**Status:** Production-ready
**Platform:** macOS M1/M2 (Docker-based build)
