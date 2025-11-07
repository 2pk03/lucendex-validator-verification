# Lucendex Validator Domain Verification

Complete guide for proper XRPL domain verification with attestation.

## Current Status

Your validator is running with basic configuration:
- ✅ Validator keys generated
- ✅ Public key in rippled.cfg: `n9LNh1zyyKdvhgu3npf4rFMHnsEXQy1q7iQEA3gcgn7WCTtQkePR`
- ❌ No attestation (not production-grade)

## Why Domain Verification Matters

Domain verification creates a **two-way cryptographic link**:
1. Domain → Validator (via xrp-ledger.toml with attestation)
2. Validator → Domain (via [validator_keys] in rippled.cfg)

This proves Lucendex controls both the domain and the validator.

## Production Setup (Recommended)

### Step 1: Install validator-keys-tool (Offline)

On your Mac (NOT on the server):

```bash
cd infra/validator/scripts
./setup-validator-keys-tool.sh
source ~/.zshrc
```

### Step 2: Generate Keys with Domain (Offline)

```bash
cd infra/validator/scripts
./generate-offline-keys.sh
```

This creates in `~/.validator-keys/`:
- `validator-keys.json` - MASTER KEY (keep offline!)
- `public_key.txt` - Public key for UNL
- `attestation.txt` - Cryptographic attestation
- `validator_token.txt` - For rippled.cfg
- `xrp-ledger.toml` - Ready to host

### Step 3: Host xrp-ledger.toml

Upload `~/.validator-keys/xrp-ledger.toml` to your web server:

**URL:** `https://lucendex.com/.well-known/xrp-ledger.toml`

**Example file:**
```toml
[[VALIDATORS]]
public_key = "n9LNh1zyyKdvhgu3npf4rFMHnsEXQy1q7iQEA3gcgn7WCTtQkePR"
attestation = "A59AB577E14A7BEC053752FBFE78C3DE..."
network = "main"
owner_country = "MT"
server_country = "NL"
```

**Requirements:**
- ✓ HTTPS required
- ✓ Path must be exactly `/.well-known/xrp-ledger.toml`
- ✓ No IP address on lucendex.com (DDoS protection)
- ✓ CORS headers recommended but not required

### Step 4: Update Validator Configuration

Edit `docker/rippled.cfg` and replace the auto-generated sections:

**Before (current):**
```ini
[validation_seed]
ssgz2Btf7BMRWDzynXMjspEk7hAj2

[validator_keys]
n9LNh1zyyKdvhgu3npf4rFMHnsEXQy1q7iQEA3gcgn7WCTtQkePR = lucendex.com
```

**After (with attestation):**
```ini
[validator_token]
<paste from ~/.validator-keys/validator_token.txt>

[validator_keys]
<new_public_key> = lucendex.com
```

### Step 5: Apply Changes

```bash
cd infra/validator
./validator-update.sh
# Select option 1: Update configuration
```

### Step 6: Verify Domain Verification

```bash
# Check xrp-ledger.toml is accessible
curl https://lucendex.com/.well-known/xrp-ledger.toml

# Check validator status
make status

# View in XRPL explorers
# https://livenet.xrpl.org/validators
```

## Simplified Current Setup (Alternative)

If you don't need attestation yet, create basic xrp-ledger.toml:

```toml
[[VALIDATORS]]
public_key = "n9LNh1zyyKdvhgu3npf4rFMHnsEXQy1q7iQEA3gcgn7WCTtQkePR"
network = "main"
```

Host at `https://lucendex.com/.well-known/xrp-ledger.toml`

**Note:** Without attestation, verification is weaker but still visible.

## Web Server Setup Examples

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name lucendex.com;
    
    location /.well-known/xrp-ledger.toml {
        alias /var/www/lucendex/.well-known/xrp-ledger.toml;
        add_header Content-Type "application/toml";
        add_header Access-Control-Allow-Origin "*";
    }
}
```

### Caddy

```caddy
lucendex.com {
    handle /.well-known/xrp-ledger.toml {
        root * /var/www/lucendex
        file_server
        header Content-Type "application/toml"
        header Access-Control-Allow-Origin "*"
    }
}
```

### Cloudflare Pages / Vercel

Add file to your static site:
```
public/.well-known/xrp-ledger.toml
```

## Security Best Practices

### Master Keys (validator-keys.json)

**DO:**
- ✓ Generate on offline machine
- ✓ Store in encrypted vault
- ✓ Backup to multiple secure locations
- ✓ Rotate quarterly

**DON'T:**
- ✗ Upload to server
- ✗ Commit to git
- ✗ Send via email/Slack
- ✗ Store in cloud without encryption

### Validator Token

**DO:**
- ✓ Store in rippled.cfg only
- ✓ Regenerate from master keys if compromised
- ✓ Keep separate from master keys

**DON'T:**
- ✗ Share publicly
- ✗ Include in xrp-ledger.toml

## Quarterly Key Rotation

Using validator-keys-tool for rotation:

```bash
# On your offline Mac
cd ~/.validator-keys
validator-keys set_domain lucendex.com --keyfile validator-keys.json

# Copy new validator_token to docker/rippled.cfg
# Run: ./validator-update.sh
```

## References

- **XRPL Docs:** https://xrpl.org/docs/infrastructure/configuration/server-modes/run-rippled-as-a-validator
- **Domain Verification:** https://xrpl.org/docs/infrastructure/configuration/server-modes/run-rippled-as-a-validator#6.-provide-domain-verification
- **xrp-ledger.toml Spec:** https://github.com/XRPLF/XRPL-Standards/blob/master/XLS-0026d-domain-verification/README.md

## Summary

**Quick Setup (Current):** Working but no attestation  
**Production Setup:** Offline keys + attestation + xrp-ledger.toml

For production, follow Steps 1-6 above to get full domain verification with cryptographic attestation.
