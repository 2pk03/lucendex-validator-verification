## Architecture & Build Plan (Neutral-Infra Patch v1)

Below updates adapt the previously drafted architecture to Lucendex's **neutral infrastructure + thin-trade bootstrap UI** strategy. Copy/paste this into your architecture section.

---

### A. Core Changes vs. Original Draft

1. **Relay is optional by default**

   * Default flow: wallet signs **and submits directly** to `rippled`.
   * Relay exists only as a convenience forwarder for **signed blobs**. No keys, ever.
   * Config: `RELAY_ENABLED=false` by default.

2. **Partner API front door (auth + quotas + metering)**

   * Add `/partner/*` endpoints gated by API-key + request signing (Ed25519) and optional mTLS for premium.
   * Per-partner rate limits in KV.
   * Usage metering to a minimal `usage_events` table for billing and SLOs.

3. **Public vs Partner surfaces**

   * `/public/*` = low-risk read + demo trade quote.
   * `/partner/*` = authenticated, higher limits, SLA-grade.

4. **Deterministic fee injection**

   * Router adds a small **routing fee (bps)**; included in the quote and the **QuoteHash** so it's tamper-evident.

5. **UI remains thin-trade demo**

   * No LP UI, no listings admin, no charts in V1.
   * Prominent label: *"Demo client — production partners use the Partner API"*.

---

### B. Updated Component Diagram (Mermaid)

```mermaid
flowchart TD
    %% GROUPS
    subgraph CLIENT["User Environment"]
        U[Browser]
        W[GemWallet / Xumm]
    end

    subgraph FE["Frontend (Thin-Trade Demo)"]
        FE1["React App (static)<br/>Served via Caddy (TLS)"]
    end

    subgraph BE["Backend (Go)"]
        APIPUB["Public API (REST)"]
        APIPARTNER["Partner API (REST/gRPC)<br/>Auth + Quotas + Metering"]
        ROUTER["Router / Pathfinder<br/>Fee-in-QuoteHash"]
        RELAY["Relay (optional)<br/>Signed blob submit only"]
        IDX["Indexer (ledger stream)"]
    end

    subgraph DATA["Data Plane"]
        KV["Custom KV (Go)<br/>Raft + TTL cache"]
        DB["PostgreSQL (canonical)"]
        OBJ["Object Storage<br/>(backups, logs)"]
    end

    %% Represent XRPL network explicitly
    subgraph XRPLNET["XRPL P2P Network"]
        R1["rippled API Node"]
        R2["rippled Full-History Node"]
        V1["XRPL Validator (Lucendex-operated)<br/>Independent & audited"]
    end

    %% CLIENT / FE
    U --> FE1
    FE1 --> APIPUB
    FE1 --> W

    %% BE reads/writes (dashed = read/subscribe, solid = write/submit)
    APIPUB --> ROUTER
    APIPARTNER --> ROUTER
    APIPARTNER --> RELAY

    ROUTER -. read-only .-> R1
    ROUTER --> KV
    ROUTER --> DB
    IDX -. stream/ws .-> R1
    IDX -. history .-> R2
    IDX --> KV
    IDX --> DB

    %% Submit path (signed blob only)
    RELAY ==> R1

    %% XRPL peering (not a parent/child)
    R1 <--> R2
    R1 <--> V1
    R2 <--> V1
```

---

### C. Partner API: Auth, Quotas, Metering

**Auth headers (Ed25519 request signing):**

```
X-Partner-Id: <uuid>
X-Request-Id: <uuid>
X-Timestamp: <RFC3339>
X-Signature: base64(Ed25519(sign(canonical_request)))
```

* Canonical request = method + path + query + body SHA256 + timestamp.
* Optional mTLS for premium plans.

**Quota keys in KV (examples):**

```
rl:partner:{id}:{bucket} -> counter (TTL window)
partner:plan:{id}        -> cached plan info (TTL)
quote:{hash}             -> serialized route (TTL)
```

**DB additions:**

```sql
CREATE TABLE partners(
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  plan TEXT NOT NULL,         -- free, pro, enterprise
  status TEXT NOT NULL,       -- active, suspended
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE api_keys(
  id UUID PRIMARY KEY,
  partner_id UUID REFERENCES partners(id),
  public_key TEXT NOT NULL,   -- Ed25519
  label TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked BOOLEAN DEFAULT FALSE
);

CREATE TABLE usage_events(
  id BIGSERIAL PRIMARY KEY,
  partner_id UUID REFERENCES partners(id),
  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  kind TEXT NOT NULL,         -- quote, submit, orderbook, route
  units INT NOT NULL,
  route_bps NUMERIC,
  meta JSONB
);
```

---

### D. API Surfaces (delta)

**Public**

* `GET /public/v1/pairs`
* `GET /public/v1/orderbook?base=XRP&quote=USD.rXYZ...`
* `POST /public/v1/quote` → `QuoteResp`

**Partner (auth required)**

* `POST /partner/v1/quote` → `QuoteResp` (higher limits, SLA)
* `POST /partner/v1/submit` → `{ tx_hash }` (signed blob only)
* `GET  /partner/v1/usage` → usage metering summary
* `GET  /partner/v1/health` → indexer freshness, router cache age, rippled lag

**Quote struct (with fee):**

```go
type Fees struct {
    RouterBps int
    EstOutFee Decimal
}

type QuoteResp struct {
    Route       Route
    Out         Decimal
    Price       Decimal
    Fees        Fees
    LedgerIndex uint32
    QuoteHash   [32]byte
    TTLLedgers  uint16
}
```

* `HashQuote` must include `Fees` fields in the canonical hash input.

---

### E. XRPL Validator Infrastructure

Lucendex will operate **one independent XRPL validator**, complementing its rippled nodes.

**Objectives:**

* Contribute to XRPL decentralization and transparency.
* Enable cryptographically signed ledger checkpoints for audit artifacts.
* Provide low-latency ledger data and reduce dependency on public nodes.

**Setup:**

| Component                | Purpose                               | Hosting                     | Security Notes                                     |
| ------------------------ | ------------------------------------- | --------------------------- | -------------------------------------------------- |
| `rippled` (API Node)     | Ledger sync + read ops                | Cloud VM / bare metal       | RPC restricted to internal network                 |
| `rippled` (Full-History) | Local AMM/orderbook replay            | Separate VM                 | Read-only, high-disk IOPS                          |
| `Validator`              | Ledger validation + signing           | Separate provider or region | Offline keypair, validator token rotated quarterly |
| `Monitoring`             | Metrics, lag detection, desync alerts | Prometheus + Grafana        | Self-healing ops via agent scripts                 |

**Cost Model (monthly est.):**

| Item                         | Est. Cost (USD)      |
| ---------------------------- | -------------------- |
| Compute (4 vCPU / 8GB RAM)   | $80–120              |
| Storage (500GB SSD + growth) | $20                  |
| Bandwidth (1–2 TB)           | $10–30               |
| Monitoring & backups         | $10–20               |
| **Total**                    | **≈ $150–200/month** |

Validator metrics integrate with the Partner API’s `/health` endpoint, so partner systems can assess **ledger freshness** and **validator participation** in real time.

---

### F. Security & Ops Additions

* Relay off by default; direct wallet submit is the recommended path.
* Per-partner SLO metrics (Prometheus labels by `partner_id`).
* Synthetic canary checks (quote + verify) every minute per critical market.
* Geofencing hook at API edge; no PII in logs, only `partner_id` for metering.
* Separate ingress: `api.lucendex.com` (partner) vs `demo.lucendex.com` (public).

---

### G. Revised Milestones (focused)

* **M0:** rippled node + indexer streaming (no UI yet)
* **M1:** DB schema + router quoting + deterministic fees
* **M2:** Public endpoints + thin-trade demo (wallet sign & direct submit)
* **M3:** Partner API (auth, quotas, metering, SLOs); relay optional-only
  * **On-Demand Order Verification**: Partners submit `ledger_index` + `tx_hash` for executed trades
  * Backend verifies transaction exists in XRPL via rippled API
  * Stores verified partner orders in `partner_orders` table for compliance
  * Enables selective backfill: only fetch specific ledgers when needed for partner disputes
* **M4:** XRPL validator live + health metrics integration
* **M5:** 2 pilot integrations (wallet + fund); polish ops

---

### H. Future Hardening (Post-Research Phase)

**Multi-Node Verification for Byzantine Fault Tolerance**

Currently, the indexer trusts a single full-history rippled node for ledger data. For enhanced security, future versions could implement:

* **Multiple rippled connections**: Connect to 3+ independent full-history nodes
* **Consensus verification**: Verify ledger hashes match across majority of nodes
* **Automatic failover**: Switch to backup node if primary returns inconsistent data
* **Byzantine detection**: Alert if nodes disagree on ledger hash (>f faults)

**Implementation Considerations**:
* Requires managing multiple WebSocket connections
* Quorum logic: 2f+1 nodes to tolerate f faults
* Increased operational complexity (3-5 nodes vs 1)
* Diminishing returns (XRPL network already provides BFT)
* Cost increase: +$192-320/month for additional nodes

**Research Required**:
* Historical analysis of XRPL node disagreements
* Cost-benefit analysis vs single trusted node
* Impact on quote latency (waiting for quorum)
* Edge cases: network partitions, slow nodes

**Priority**: Low for V1 (single trusted node sufficient), evaluate post-pilot based on partner requirements and incident data.
