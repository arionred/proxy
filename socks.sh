#!/usr/bin/env bash
# Auto-installer for SOCKS5 (Dante) with fixed configuration

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use: sudo $0"
    exit 1
fi

# Get public IP
PUBLIC_IP=$(curl -4 -s https://api.ipify.org || curl -4 -s https://icanhazip.com)
if [[ -z "$PUBLIC_IP" ]]; then
    echo "Could not determine public IP address"
    exit 1
fi

# Fixed configuration
USERNAME="admin"
PASSWORD="6789admin"
PORT=6789
EXT_IF=$(ip route | awk '/default/ {print $5; exit}')
EXT_IF=${EXT_IF:-eth0}

echo "Starting SOCKS5 installation with fixed configuration"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "Port: $PORT"

# Install required packages
apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y dante-server iptables

# Create user
if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -M -N -s /usr/sbin/nologin "$USERNAME"
fi
echo "${USERNAME}:${PASSWORD}" | chpasswd

# Create Dante configuration
cat > /etc/danted.conf <<EOF
# Dante SOCKS5 server configuration
internal: 0.0.0.0 port = $PORT
external: $EXT_IF
method: pam
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    protocol: tcp udp
}
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable danted
systemctl restart danted

# Configure firewall
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp
else
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

# Display connection information
echo ""
echo "==================================================="
echo "✅ SOCKS5 Proxy Installed Successfully"
echo "==================================================="
echo "Server IP:    $PUBLIC_IP"
echo "Port:         $PORT"
echo "Username:     $USERNAME"
echo "Password:     $PASSWORD"
echo "==================================================="
echo "Usage:        $PUBLIC_IP:$PORT:$USERNAME:$PASSWORD:socks"
echo "==================================================="
echo ""
echo "Service Management: sudo systemctl {start|stop|restart|status} danted"
