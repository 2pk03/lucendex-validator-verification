#!/bin/bash
set -euo pipefail

# XRPL Validator VM Setup and Hardening Script
# Run this after VM is provisioned

echo "Starting VM setup and hardening..."

# Wait for cloud-init to fully complete
echo "Waiting for cloud-init to complete (this may take 2-3 minutes)..."
cloud-init status --wait || true

# Give cloud-init processes time to finish
sleep 10

# Wait for ALL package managers to finish
echo "Ensuring all package locks are cleared..."
max_wait=60
waited=0
while [ $waited -lt $max_wait ]; do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
       ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
       ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
        echo "✓ All package locks cleared"
        break
    fi
    echo "Waiting for package locks to clear..."
    sleep 5
    waited=$((waited + 5))
done

if [ $waited -ge $max_wait ]; then
    echo "Warning: Package locks still present, killing processes..."
    pkill -9 apt-get || true
    pkill -9 dpkg || true
    sleep 5
fi

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Configure timezone
timedatectl set-timezone UTC

# Configure zram swap (25% of RAM)
echo "Configuring zram swap..."
apt-get install -y linux-modules-extra-$(uname -r)
modprobe zram
apt-get update && apt-get install -y zram-tools
cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=25
EOF
systemctl enable zramswap
systemctl restart zramswap
echo "✓ zram swap configured (25% of RAM)"

# Configure sysctl for performance and security
echo "Configuring kernel parameters..."
cat > /etc/sysctl.d/99-xrpl-validator.conf <<EOF
# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr

# Security hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1

# File handles
fs.file-max = 2097152
fs.nr_open = 2097152
EOF

# Apply sysctl with --ignore flag for missing parameters
sysctl --system 2>/dev/null || sysctl -p /etc/sysctl.d/99-xrpl-validator.conf 2>/dev/null || true

# Set file limits
echo "Configuring file limits..."
cat > /etc/security/limits.d/xrpl-validator.conf <<EOF
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

# Configure fail2ban (if not already configured by cloud-init)
if systemctl list-unit-files | grep -q fail2ban.service; then
    echo "Configuring fail2ban..."
    systemctl enable fail2ban
    systemctl start fail2ban
    
    # Create fail2ban jail for SSH
    cat > /etc/fail2ban/jail.d/sshd.conf <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    systemctl restart fail2ban
    echo "✓ fail2ban configured"
else
    echo "✓ fail2ban already configured by cloud-init"
fi

# Harden SSH
echo "Hardening SSH configuration..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config

# Add these if not present
grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config

systemctl restart sshd

# Configure UFW firewall
echo "Configuring firewall rules..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 51235/tcp comment 'XRPL peer-to-peer'
echo "y" | ufw enable

# Install monitoring tools
echo "Installing monitoring tools..."
apt-get install -y \
    htop \
    iotop \
    sysstat \
    ncdu \
    nethogs \
    jq

# Enable sysstat
systemctl enable sysstat
systemctl start sysstat

# Create directories
echo "Creating application directories..."
mkdir -p /opt/rippled
mkdir -p /var/log/validator

# Set up log rotation
echo "Configuring log rotation..."
cat > /etc/logrotate.d/validator <<EOF
/var/log/validator/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
}
EOF

# Disable unnecessary services
echo "Disabling unnecessary services..."
systemctl disable bluetooth.service 2>/dev/null || true
systemctl stop bluetooth.service 2>/dev/null || true

# Set hostname in /etc/hosts
echo "Configuring hostname..."
hostnamectl set-hostname xrpl-validator
echo "127.0.1.1 xrpl-validator" >> /etc/hosts

# Install Docker prerequisites
echo "Installing Docker prerequisites..."
# Wait for any package managers to finish
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
    echo "Waiting for package lock..."
    sleep 5
done
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "✓ VM setup and hardening complete!"
echo "Next: Run install-docker.sh to install Docker"
