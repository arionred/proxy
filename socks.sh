#!/bin/bash
# Auto-installer for SOCKS5 (Dante) with fixed configuration

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use: sudo $0"
    exit 1
fi

# Fixed configuration
USERNAME="admin"
PASSWORD="6789admin"
PORT=6789

# Get public IP and network interface
PUBLIC_IP=$(curl -4 -s https://api.ipify.org || curl -4 -s https://icanhazip.com)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
EXT_IF=$(ip route | awk '/default/ {print $5; exit}')
EXT_IF=${EXT_IF:-eth0}

echo "Installing SOCKS5 server..."
echo "Configuration:"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "Port: $PORT"

# Install required packages
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y dante-server iptables

# Create user
if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -M -N -s /usr/sbin/nologin "$USERNAME"
fi
echo "${USERNAME}:${PASSWORD}" | chpasswd

# Create Dante configuration
cat > /etc/danted.conf <<EOF
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
}
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable danted
systemctl restart danted

# Configure firewall
if command -v ufw >/dev/null; then
    ufw allow $PORT/tcp
else
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
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
echo "Service Management:"
echo "sudo systemctl start danted"
echo "sudo systemctl stop danted"
echo "sudo systemctl status danted"
