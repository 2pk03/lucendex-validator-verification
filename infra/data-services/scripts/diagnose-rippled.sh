#!/bin/bash
# Lucendex Data Services - rippled Diagnostics
# Check for OOM kills, memory issues, and sync status

set -euo pipefail

echo "=== Lucendex Data Services Diagnostics ==="
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Check if running as root or with docker permissions
if ! docker ps >/dev/null 2>&1; then
    echo "ERROR: Cannot access Docker. Run as root or with docker group membership."
    exit 1
fi

# Check OOM kills
echo "=== Checking for OOM Kills ==="
if dmesg | grep -i "killed process.*rippled" | tail -5; then
    echo "⚠️  WARNING: rippled processes have been OOM killed!"
    echo ""
else
    echo "✓ No OOM kills detected"
    echo ""
fi

# Check disk space
echo "=== Disk Space ==="
df -h | grep -E "Filesystem|/var/lib/docker|/$"
echo ""

# Check container resource usage
echo "=== Container Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo ""

# Check container restart counts
echo "=== Container Restart Counts ==="
for container in lucendex-rippled-api lucendex-rippled-history lucendex-postgres; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        restarts=$(docker inspect ${container} | jq -r '.[0].RestartCount')
        state=$(docker inspect ${container} | jq -r '.[0].State.Status')
        echo "${container}: ${restarts} restarts (state: ${state})"
    else
        echo "${container}: NOT FOUND"
    fi
done
echo ""

# Check rippled API node sync status
echo "=== rippled API Sync Status ==="
if docker exec lucendex-rippled-api rippled server_info 2>/dev/null | jq -r '.result | {state: .info.server_state, ledgers: .info.complete_ledgers, peers: .info.peers, uptime: .info.uptime}'; then
    echo ""
else
    echo "⚠️  Failed to query API node"
    echo ""
fi

# Check rippled history node sync status
echo "=== rippled Full-History Sync Status ==="
if docker exec lucendex-rippled-history rippled server_info 2>/dev/null | jq -r '.result | {state: .info.server_state, ledgers: .info.complete_ledgers, peers: .info.peers, uptime: .info.uptime}'; then
    echo ""
else
    echo "⚠️  Failed to query history node"
    echo ""
fi

# Check recent container logs for errors
echo "=== Recent Errors in Logs (last 50 lines) ==="
echo "--- API Node ---"
docker logs --tail 50 lucendex-rippled-api 2>&1 | grep -i "error\|warn\|fatal" | tail -10 || echo "No recent errors"
echo ""
echo "--- History Node ---"
docker logs --tail 50 lucendex-rippled-history 2>&1 | grep -i "error\|warn\|fatal" | tail -10 || echo "No recent errors"
echo ""

# Check system memory pressure
echo "=== System Memory Status ==="
free -h
echo ""

# Check Docker volume sizes
echo "=== Docker Volume Sizes ==="
docker system df -v | grep -A 20 "Local Volumes" | grep rippled || echo "No rippled volumes found"
echo ""

echo "=== Diagnostics Complete ==="
echo ""
echo "If issues persist:"
echo "1. Check full logs: docker logs lucendex-rippled-history"
echo "2. Check config: docker exec lucendex-rippled-history cat /etc/opt/ripple/rippled.cfg"
echo "3. Monitor in real-time: docker stats"
echo "4. Check dmesg for kernel errors: dmesg | tail -50"
