#!/usr/bin/env bash
# Auto-installer for SOCKS5 (Dante) with fixed configuration

set -euo pipefail

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a /var/log/socks5-installer.log
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use: sudo $0"
    fi
}

# Get network interface and public IP
get_network_info() {
    EXT_IF=$(ip route | awk '/default/ {print $5; exit}')
    EXT_IF=${EXT_IF:-eth0}
    
    PUBLIC_IP=$(curl -4 -s --connect-timeout 10 https://api.ipify.org)
    
    if [[ -z "$PUBLIC_IP" ]] || ! [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IP=$(curl -4 -s --connect-timeout 10 https://icanhazip.com)
    fi
    
    if [[ -z "$PUBLIC_IP" ]] || ! [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error_exit "Could not determine public IP address"
    fi
    
    log "Network interface: $EXT_IF, Public IP: $PUBLIC_IP"
}

# Firewall management
manage_firewall() {
    local port=$1
    local protocol=${2:-tcp}
    
    log "Opening firewall for port $port/$protocol"
    
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow "$port/$protocol" >/dev/null 2>&1 || true
    else
        if ! dpkg -l | grep -q iptables-persistent; then
            DEBIAN_FRONTEND=noninteractive sudo apt-get install -y iptables-persistent
        fi
        sudo iptables -I INPUT -p "$protocol" --dport "$port" -j ACCEPT
        sudo netfilter-persistent save >/dev/null 2>&1 || sudo iptables-save > /etc/iptables/rules.v4
    fi
}

# Install SOCKS5 with fixed configuration
install_socks5() {
    local USERNAME="admin"
    local PASSWORD="6789admin"
    local PORT=6789
    
    log "Starting SOCKS5 installation with fixed configuration"
    log "Username: $USERNAME"
    log "Password: $PASSWORD"
    log "Port: $PORT"

    # Install required packages
    log "Installing required packages"
    sudo apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y dante-server curl iptables

    # Create user
    if ! id "$USERNAME" >/dev/null 2>&1; then
        sudo useradd -M -N -s /usr/sbin/nologin "$USERNAME"
    fi
    echo "${USERNAME}:${PASSWORD}" | sudo chpasswd

    # Backup existing config
    if [[ -f /etc/danted.conf ]]; then
        sudo cp /etc/danted.conf "/etc/danted.conf.bak.$(date +%F_%T)"
    fi

    # Create Dante configuration
    sudo tee /etc/danted.conf >/dev/null <<EOF
# Dante SOCKS5 server configuration
logoutput: syslog /var/log/danted.log

# Network configuration
internal: 0.0.0.0 port = $PORT
external: $EXT_IF

# Authentication method
method: pam

# User privileges
user.privileged: root
user.notprivileged: nobody

# Client rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
    protocol: tcp udp
}
EOF

    sudo chmod 644 /etc/danted.conf

    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable danted
    sudo systemctl restart danted

    # Verify service is running
    sleep 2
    if ! systemctl is-active --quiet danted; then
        error_exit "SOCKS5 service failed to start"
    fi

    # Configure firewall
    manage_firewall "$PORT" tcp

    log "SOCKS5 installation completed successfully"
    
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
}

# Main execution
main() {
    log "Starting SOCKS5 server installation script"
    
    # Initial checks
    check_root
    get_network_info
    
    # Install SOCKS5 with fixed configuration
    install_socks5
    
    # Final status
    log "Installation script completed successfully"
    echo "📝 Installation log saved to: /var/log/socks5-installer.log"
    echo "🔧 Service Management: sudo systemctl {start|stop|restart|status} danted"
}

# Execute main function
main "$@"
