# Lucendex Indexer - Technical Documentation

## Overview

The Lucendex indexer is a specialized component that monitors the XRPL blockchain for DEX-related transactions (AMM operations and orderbook offers) and maintains a PostgreSQL database with current liquidity state.

## Core Capabilities

### 1. Real-Time Ledger Streaming
- WebSocket connection to rippled full-history node
- Subscribes to `ledger` stream for close notifications
- Fetches full ledger data with transactions on each close
- Processing time: 100-500ms per ledger (40-150 txns typical)

### 2. Transaction Filtering
**Processes Only DEX Transactions**:
- `AMMCreate`, `AMMDeposit`, `AMMWithdraw` - AMM pool operations
- `OfferCreate` - New orderbook offers
- `OfferCancel` - Cancel existing offers

**Ignores All Other Transactions**:
- Payments, trust lines, account settings, etc.
- No PII, no user data, no custody information
- KYC-compliant by design (public blockchain data only)

### 3. State Management

**AMM Pools** (`core.amm_pools`):
- Current reserves (Asset1, Asset2)
- Trading fee (bps)
- Latest ledger state only (no history)

**Orderbook Offers** (`core.orderbook_state`):
- Active offers: price, amount, owner
- Cancelled offers: marked `status='cancelled'`
- Invalid transactions: marked `status='invalid_parse'` with error in `meta` JSONB

**Ledger Checkpoints** (`core.ledger_checkpoints`):
- Ledger index, hash, timestamp
- Transaction count, processing duration
- Used for resumption after restart

### 4. Crash Recovery

**No Historical Backfill Required**:
- DEX routing only needs current state
- Gap detection logs missing ledgers but doesn't backfill
- Resumes from current validated ledger
- AMM pools and offers are updated idempotently

**Rationale**:
- Old AMM reserves are irrelevant (only current matters)
- Old cancelled offers are irrelevant (only active matters)
- Router computes paths from current state, not history

### 5. Data Integrity

**Duplicate Prevention**:
- Checks if ledger already processed before processing
- `ON CONFLICT DO UPDATE` for idempotent upserts
- Skips re-processing automatically

**Audit Trail**:
- All transactions stored with meta JSONB
- Invalid transactions logged with error reason
- Complete ledger checkpoint history

**SSL Encryption**:
- All database connections use `sslmode=require`
- Self-signed certificates for internal traffic

### 6. Observability

**Logging Modes**:
- **Normal**: Ledger processing, AMM/offer updates, errors
- **Verbose** (`-v` or `VERBOSE=true`): Transaction-level details, skipped txns

**Metrics** (Log-Based):
- Processing duration per ledger
- Transaction count per ledger
- Gap size on restart
- Backfill count (if implemented)

**Log Rotation**:
- Daily rotation
- 7-day retention
- Compressed archives

## Architecture Decisions

### Why No Historical Backfill?

**Current Design** (Correct for DEX):
1. On restart with gap: Log warning, resume from current ledger
2. Current AMM/offer state rebuilds quickly from live stream
3. Router quotes based on current liquidity only

**Alternative** (Rejected):
1. Backfill all missing ledgers
2. Compute exact state at gap point
3. Issues: Slow, unnecessary, adds complexity

### Duplicate Handling Strategy

**Keep Newest, Overwrite Oldest**:
- `ON CONFLICT (unique_key) DO UPDATE SET ... = EXCLUDED...`
- Correct for idempotency
- Handles network retries gracefully

## Performance

**Typical Metrics**:
- Processing: 100-500ms per ledger
- Transactions: 40-150 per ledger
- Throughput: ~3-4 ledgers per second (matches XRPL close time)

**Resource Usage**:
- Memory: ~5-10MB
- CPU: <1% (6 vCPU VM)
- Database connections: 1 active

## Operational Commands

```bash
cd infra/data-services

# Deployment
make indexer-deploy        # Build and deploy

# Control
make indexer-start
make indexer-stop
make indexer-restart

# Monitoring
make indexer-status        # Systemd status
make indexer-logs          # Follow logs

# Configuration
make indexer-verbose-on    # Enable debug logging
make indexer-verbose-off   # Disable debug logging
make update-indexer-env    # Update environment

# Version
./indexer -version         # Show version
```

## Future Enhancements

### Considered but Deferred to V1.1+

**Multi-Node Verification**:
- Connect to 3+ rippled nodes
- Verify ledger hashes via quorum
- Byzantine fault tolerance
- Priority: Low (XRPL already provides BFT)

**Prometheus Metrics**:
- Gauge: indexer_current_ledger
- Counter: indexer_ledgers_processed_total
- Histogram: indexer_ledger_processing_duration_seconds
- Priority: Medium (useful for SLO monitoring)

**Stateful Backfill**:
- Resume interrupted backfill
- Persistent backfill progress table
- Priority: Low (not needed if no backfill)

## Security Considerations

**Data Minimization**:
- Only DEX transactions stored
- No wallet balances, no payment trails
- No user identities or IP addresses

**Integrity**:
- Duplicate detection prevents data corruption
- Checkpoint continuity verifies chain integrity
- Audit trail for compliance

**Operational Security**:
- Least-privilege database role (`indexer_rw`)
- SSL/TLS for all database traffic
- Log rotation prevents disk exhaustion
- Systemd hardening (NoNewPrivileges, ProtectSystem)

## Version History

**v1.0.0-alpha** (2025-11-06):
- Initial production release
- Gap detection (log only, no backfill)
- Duplicate prevention
- Audit trail with meta JSONB
- Verbose logging toggle
- Log rotation (7-day)
- SSL encryption
