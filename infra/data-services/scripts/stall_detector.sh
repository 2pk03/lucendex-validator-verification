#!/usr/bin/env bash
set -euo pipefail

# Rippled sync stall detector
# Monitors validated ledger sequence and alerts if no progress

CONTAINER="${CONTAINER:-lucendex-rippled-api}"
PORT="${PORT:-51234}"
DUR="${DUR:-600}"
INTERVAL="${INTERVAL:-15}"
STALL_SECONDS="${STALL_SECONDS:-180}"

end=$((SECONDS + DUR))
last_seq=-1
stalled_for=0

jq_val() { jq -r "$1" 2>/dev/null || echo ""; }

get_seq() {
  local json="$1"
  local seq
  seq="$(printf '%s' "$json" | jq_val '.result.info.validated_ledger.seq')"
  if [[ -n "${seq}" && "${seq}" != "null" ]]; then
    echo "${seq}"
    return
  fi
  local rng
  rng="$(printf '%s' "$json" | jq_val '.result.info.complete_ledgers')"
  if [[ -z "$rng" || "$rng" == "empty" || "$rng" == "null" ]]; then
    echo "0"
    return
  fi
  echo "$rng" | awk -F, '{print $NF}' | awk -F- '{print $NF+0}'
}

while (( SECONDS < end )); do
  si="$(docker exec "$CONTAINER" sh -lc \
    "curl -s -H 'Content-Type: application/json' -d '{\"method\":\"server_info\"}' http://127.0.0.1:${PORT}")" || {
      echo "ERROR: server_info RPC failed"; exit 3; }

  state="$(printf '%s' "$si" | jq_val '.result.info.server_state')"
  fetch_pack="$(printf '%s' "$si" | jq_val '.result.info.fetch_pack // 0')"
  seq="$(get_seq "$si")"
  ts="$(date -u +%H:%M:%S)"

  printf '[%s] state=%s seq=%s fetch_pack=%s\n' "$ts" "${state:-unknown}" "${seq:-0}" "${fetch_pack:-0}"

  if [[ "$last_seq" -ge 0 && "$seq" -le "$last_seq" ]]; then
    stalled_for=$((stalled_for + INTERVAL))
    if (( stalled_for >= STALL_SECONDS )); then
      echo "WARN: validated ledger has not advanced for ${stalled_for}s (seq stuck at ${seq})."
      echo "HINTS: check peers/admin RPC, disk IOPS, outbound egress, time sync (NTP), and that ports 2459/51235 (peer) are open."
      echo "RESULT: STALLED"
      exit 2
    fi
  else
    stalled_for=0
  fi

  last_seq="$seq"
  sleep "$INTERVAL"
done

echo "RESULT: OK (no stall ≥ ${STALL_SECONDS}s within ${DUR}s)"
