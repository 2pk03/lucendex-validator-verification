#!/bin/bash
# Setup script for Lucendex Data Services VM
# Installs Docker, configures system, prepares for service deployment

set -euo pipefail

echo "=== Lucendex Data Services VM Setup ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install essential tools
echo "Installing essential tools..."
apt-get install -y jq

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable Docker service
    systemctl enable docker
    systemctl start docker
    
    echo "✓ Docker installed successfully"
else
    echo "✓ Docker already installed"
fi

# Verify Docker installation
docker --version
docker compose version

# Create directory structure
echo "Creating directory structure..."
mkdir -p /opt/lucendex/{docker,logs,backups,data}
chown -R root:root /opt/lucendex
chmod 755 /opt/lucendex

# Create validators.txt for rippled
echo "Creating validators.txt..."
cat > /opt/lucendex/docker/validators.txt <<'EOF'
# XRPL Mainnet Validators
[validators]
nHBk5DPexBjinXV8qHn7SEKzoxh2W92FxSbNTPgGtQYBzEF4msn9 Alloy Networks
nHUpJSKQTZdB1TDkbCREMuf8vEqFkk84BcvZDhsQsDufFDQVajam Ripple
nHUeUNs3aHF6X3eiTsb4xYu1dFm8WN2dTTbT8RxUvKVvXqJ4vUss Ripple
nHBdXSF6YHAHSZUk7rvox6jwbvvyqBnsWGcewBtq8x1XuH6KXKXr Ripple
nHUtNnLVx7odrz5dnfb2xpIgbEeJPbzJWfdicSkGyVw1eE5GNB8Z Ripple
nHU5egMCYs0YHi1KRFK8uf4RBFkvKfEqhSSZQ3uA3E2GgxWtKRmW Gatehub
nHDwHQGjKTz6R6pFigSSrNBrhNYyUGFPHA75HiTccTCQzuu9d7Za XRPL Labs
nHUnhRJK3csknycNK5SXRFi4jvDp1XQBdxPQRGF3A9PSKvvGhfgU Bithomp
nHUED59jjpQ5QbNhesXMhqii9gA8UfbBmv3i5StgyxG98qjsT4yn Coil
EOF

# Set up log rotation
echo "Configuring log rotation..."
cat > /etc/logrotate.d/lucendex <<'EOF'
/opt/lucendex/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        docker compose -f /opt/lucendex/docker/docker-compose.yml restart > /dev/null 2>&1 || true
    endscript
}
EOF

# Configure system limits for rippled
echo "Configuring system limits..."
cat >> /etc/security/limits.conf <<'EOF'
# Lucendex Data Services limits
*    soft nofile 65536
*    hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

# Configure zram swap (50% of RAM for heavy workloads)
echo "Configuring zram swap..."
apt-get install -y linux-modules-extra-$(uname -r)
modprobe zram
apt-get update && apt-get install -y zram-tools
cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=50
EOF
systemctl enable zramswap
systemctl restart zramswap
echo "✓ zram swap configured (50% of RAM)"

# Configure sysctl for performance
echo "Configuring kernel parameters..."
cat >> /etc/sysctl.conf <<'EOF'

# Lucendex Data Services kernel tuning
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF
sysctl -p

# Create systemd service for auto-start
echo "Creating systemd service..."
cat > /etc/systemd/system/lucendex-data-services.service <<'EOF'
[Unit]
Description=Lucendex Data Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/lucendex/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lucendex-data-services.service

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "1. Copy docker-compose.yml and configs to /opt/lucendex/docker/"
echo "2. Create .env file with passwords"
echo "3. Start services: systemctl start lucendex-data-services"
echo ""
