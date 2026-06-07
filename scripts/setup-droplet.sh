#!/bin/bash
# =============================================================================
# Shipyard - Droplet Setup Script
# =============================================================================
# Provisions a fresh Ubuntu VPS with Docker + Caddy.
# Run this ONCE on a new droplet.
#
# Usage:
#   bash setup-droplet.sh --domain example.com --subdomains "www,app" --mysql false
#
# Or remotely:
#   ssh root@IP "bash <(curl -s https://raw.githubusercontent.com/sjpavlis/shipyard/main/scripts/setup-droplet.sh)" \
#     --domain example.com --subdomains "www,app"
# =============================================================================

set -e

# =============================================================================
# Parse arguments
# =============================================================================
DOMAIN=""
SUBDOMAINS=""
INSTALL_MYSQL=false
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift 2 ;;
    --subdomains) SUBDOMAINS="$2"; shift 2 ;;
    --mysql) INSTALL_MYSQL="$2"; shift 2 ;;
    --db-name) DB_NAME="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$DOMAIN" ]; then
  echo "Error: --domain is required"
  echo "Usage: bash setup-droplet.sh --domain example.com [--subdomains 'www,app'] [--mysql true]"
  exit 1
fi

echo "============================================="
echo " 🚢 Shipyard - Droplet Setup"
echo "============================================="
echo " Domain:     $DOMAIN"
echo " Subdomains: ${SUBDOMAINS:-none}"
echo " MySQL:      $INSTALL_MYSQL"
echo "============================================="
echo ""

# =============================================================================
# 1. System update
# =============================================================================
echo "📦 Updating system packages..."
apt update && apt upgrade -y

# =============================================================================
# 2. Install Docker
# =============================================================================
echo "🐳 Installing Docker..."
if command -v docker &> /dev/null; then
  echo "  Docker already installed: $(docker --version)"
else
  apt install -y docker.io
  systemctl enable docker
  systemctl start docker
  echo "  Docker installed: $(docker --version)"
fi

# =============================================================================
# 3. Install Caddy
# =============================================================================
echo "🔒 Installing Caddy..."
if command -v caddy &> /dev/null; then
  echo "  Caddy already installed: $(caddy version)"
else
  apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt update
  apt install -y caddy
  echo "  Caddy installed: $(caddy version)"
fi

# =============================================================================
# 4. Install MySQL (optional)
# =============================================================================
if [ "$INSTALL_MYSQL" = "true" ]; then
  echo "🗄️  Installing MySQL..."
  if command -v mysql &> /dev/null; then
    echo "  MySQL already installed"
  else
    apt install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
    echo "  MySQL installed"
  fi

  # Create database and user if specified
  if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; then
    echo "  Creating database '$DB_NAME' and user '$DB_USER'..."
    # Use printf to safely handle special characters in passwords
    ESCAPED_PASS=$(printf '%s' "$DB_PASSWORD" | sed "s/'/''/g")
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$ESCAPED_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
    echo "  Database and user created."
  fi
fi

# =============================================================================
# 5. Generate SSH deploy key
# =============================================================================
echo "🔑 Setting up SSH deploy key..."
if [ -f ~/.ssh/deploy_key ]; then
  echo "  Deploy key already exists"
else
  ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -C "shipyard-deploy" -N ""
  cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys
  echo "  Deploy key generated"
fi

# =============================================================================
# 6. Configure Caddy
# =============================================================================
echo "⚙️  Configuring Caddy..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/setup-caddy.sh" ]; then
  bash "$SCRIPT_DIR/setup-caddy.sh" --domain "$DOMAIN" --subdomains "$SUBDOMAINS"
else
  # Inline basic Caddy config if setup-caddy.sh isn't available
  cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy localhost:8080
}
EOF

  # Add www redirect
  cat >> /etc/caddy/Caddyfile <<EOF

www.$DOMAIN {
    redir https://$DOMAIN{uri} permanent
}
EOF

  systemctl restart caddy
fi

echo ""
echo "============================================="
echo " ✅ Shipyard Setup Complete!"
echo "============================================="
echo ""
echo " Next steps:"
echo ""
echo " 1. Add DNS A records pointing to this server's IP:"
echo "    - @ → $(curl -s ifconfig.me)"
echo "    - www → $(curl -s ifconfig.me)"
if [ -n "$SUBDOMAINS" ]; then
  IFS=',' read -ra SUBS <<< "$SUBDOMAINS"
  for sub in "${SUBS[@]}"; do
    sub=$(echo "$sub" | xargs)  # trim whitespace
    echo "    - $sub → $(curl -s ifconfig.me)"
  done
fi
echo ""
echo " 2. Add this SSH private key to your GitHub Secrets as DROPLET_SSH_KEY:"
echo ""
cat ~/.ssh/deploy_key
echo ""
echo ""
echo " 3. Add DROPLET_HOST=$(curl -s ifconfig.me) to your GitHub Secrets"
echo ""
echo "============================================="
