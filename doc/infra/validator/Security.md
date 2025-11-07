# XRPL Validator Security Guide

## Docker Image Verification

### ⚠️ Critical Security Issue

**NEVER use `:latest` tags in production!** This exposes you to:
- Supply chain attacks
- Malicious image injection
- Unverified updates
- Code tampering

### Our Security Approach

We use **SHA256 digest pinning** to ensure image authenticity:

```yaml
# ❌ INSECURE (what we had before)
image: rippleci/rippled:latest

# ✅ SECURE (what we use now)
image: rippleci/rippled@sha256:467dde2bf955dba05aafb2f6020bfd8eacf64cd07305b41d7dfc3c8e12df342d
```

## Image Verification Process

### Before Any Deployment or Update

1. **Run Verification Script**
   ```bash
   cd infra/validator
   make verify-image
   ```

   This script:
   - Pulls image with SHA256 digest verification
   - Compares against known good digest
   - Runs security vulnerability scan
   - Provides links to official sources

2. **Manual Verification Steps**

   **Step 1: Check Docker Hub (Official Source)**
   - Visit: https://hub.docker.com/r/rippleci/rippled/tags
   - Find the specific version tag (e.g., 2.3.0, 2.2.0)
   - Copy the SHA256 digest from "OS/ARCH" details
   - **Compare with our pinned digest**

   **Step 2: Verify on GitHub**
   - Visit: https://github.com/XRPLF/rippled/releases
   - Check release notes for the version
   - Verify Docker images are built by official CI

   **Step 3: Cross-reference Documentation**
   - Visit: https://xrpl.org/install-rippled-on-ubuntu.html
   - Confirm recommended versions
   - Check for security advisories

### Docker Content Trust (Recommended)

Enable Docker Content Trust for automatic signature verification:

```bash
# Enable globally
export DOCKER_CONTENT_TRUST=1

# Add to your shell profile
echo 'export DOCKER_CONTENT_TRUST=1' >> ~/.zshrc

# Verify it's enabled
docker pull rippleci/rippled@sha256:...
# Will show: "Pull (1 of 1): rippleci/rippled@sha256:..."
```

## Updating to New Versions

### Safe Update Process

1. **Check for New Release**
   ```bash
   # Check official sources
   open https://github.com/XRPLF/rippled/releases
   open https://hub.docker.com/r/rippleci/rippled/tags
   ```

2. **Verify New Image**
   - Get SHA256 digest from Docker Hub
   - Update `scripts/verify-rippled-image.sh`:
     ```bash
     RECOMMENDED_TAG="2.3.0"  # New version
     OFFICIAL_DIGEST="sha256:NEW_DIGEST_HERE"
     ```

3. **Run Verification**
   ```bash
   make verify-image
   ```

4. **Update docker-compose.yml**
   ```yaml
   image: rippleci/rippled@sha256:NEW_DIGEST_HERE
   ```

5. **Test Locally** (if possible)
   ```bash
   # Pull and test new image
   docker-compose -f docker/docker-compose.yml config
   ```

6. **Deploy Update**
   ```bash
   # Backup current config first
   make backup

   # Upload new docker-compose.yml
   scp -i terraform/validator_ssh_key \
       docker/docker-compose.yml \
       root@$(cd terraform && terraform output -raw validator_ip):/opt/rippled/

   # Restart with new image
   make restart
   
   # Monitor startup
   make logs
   ```

7. **Verify Update**
   ```bash
   # Check version
   make version
   
   # Check status
   make status
   
   # Monitor for 30 minutes
   make health
   ```

## Security Checklist

### Before Every Deployment

- [ ] SHA256 digest verified against Docker Hub
- [ ] GitHub release notes reviewed
- [ ] No critical security advisories
- [ ] Image scanned for vulnerabilities
- [ ] Docker Content Trust enabled (optional but recommended)
- [ ] Backup created before update
- [ ] Change tested in non-production (if available)

### During Deployment

- [ ] Image pulled with digest verification
- [ ] Container starts successfully
- [ ] No errors in logs
- [ ] Validator connects to network
- [ ] RPC responding correctly

### After Deployment

- [ ] Monitor logs for 30 minutes
- [ ] Check validator status
- [ ] Verify peer connections
- [ ] Confirm proposing/validating
- [ ] No unusual resource usage

## Additional Security Measures

### Container Security

Our docker-compose.yml includes:

```yaml
# Drop all capabilities by default
cap_drop:
  - ALL

# Add only required capabilities
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID

# Prevent privilege escalation
security_opt:
  - no-new-privileges:true

# Resource limits
mem_limit: 6g
cpus: 3.5
```

### Network Security

- RPC/WebSocket bound to localhost only (127.0.0.1)
- Only peer port (51235) exposed publicly
- Firewall configured via UFW
- fail2ban monitoring SSH attempts

### File System Security

- Configuration mounted read-only: `:ro`
- Data volumes isolated
- No unnecessary file access

## Incident Response

### If You Suspect Compromise

1. **Immediately Stop Container**
   ```bash
   make stop
   ```

2. **Backup Everything**
   ```bash
   make backup
   ssh -i terraform/validator_ssh_key root@IP "tar czf /tmp/forensics.tar.gz /opt/rippled/"
   ```

3. **Investigate**
   - Check Docker image digest
   - Review container logs
   - Examine file modifications
   - Check network connections

4. **Recovery**
   - Destroy and rebuild from known-good image
   - Review all changes made
   - Update all credentials
   - Report to Ripple if official image compromised

## Official Sources

### Trust Only These Sources

1. **Docker Hub**
   - https://hub.docker.com/r/rippleci/rippled
   - Official Ripple CI builds
   - Signed and scanned

2. **GitHub**
   - https://github.com/XRPLF/rippled
   - Source code repository
   - Release notes and tags

3. **XRPL.org**
   - https://xrpl.org/
   - Official documentation
   - Security advisories

### Contact for Security Issues

- **Ripple Security**: security@ripple.com
- **XRPL Foundation**: https://xrplf.org/contact
- **Bug Bounty**: https://ripple.com/bug-bounty/

## Automation

### Automated Security Checks (Future)

Consider implementing:

1. **Daily Digest Verification**
   ```bash
   # Cron job to verify running image
   0 2 * * * cd /opt/rippled && docker inspect rippled | grep Digest
   ```

2. **Security Scan Integration**
   ```bash
   # Integrate with CI/CD
   docker scan --severity high rippleci/rippled@sha256:...
   ```

3. **Alerting**
   - Monitor for new releases
   - Alert on security advisories
   - Detect unexpected image changes

## Best Practices

1. **Never blindly update** - Always verify first
2. **Pin digests, not tags** - Tags can be moved, digests cannot
3. **Enable Docker Content Trust** - Automated signature verification
4. **Regular security scans** - Check for vulnerabilities
5. **Monitor official sources** - Stay informed on releases
6. **Maintain backups** - Always backup before updates
7. **Test updates** - In non-production if possible
8. **Document changes** - Keep update log
9. **Review logs** - Monitor for anomalies
10. **Report issues** - Help the community

## Verification Script Usage

```bash
# Basic verification
make verify-image

# Full manual process
cd infra/validator/scripts
./verify-rippled-image.sh

# Check current image
docker image inspect rippleci/rippled:2.3.0 --format='{{index .RepoDigests 0}}'

# Verify signature (with Content Trust)
DOCKER_CONTENT_TRUST=1 docker pull rippleci/rippled@sha256:...
```

## Questions?

- Review XRPL documentation: https://xrpl.org/
- Join XRPL Dev Discord: https://xrpldevs.org/
- Read security advisories: https://github.com/XRPLF/rippled/security/advisories
- Contact Ripple security team: security@ripple.com
