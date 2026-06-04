#!/bin/bash
# =============================================================================
# Shipyard - MySQL Setup
# =============================================================================
# Installs MySQL and creates a database + user.
# Run this on the VPS after setup-droplet.sh if your app needs MySQL.
#
# Usage:
#   bash setup-mysql.sh --db-name mydb --db-user myuser --db-password secret123
#
# Or import an existing dump:
#   bash setup-mysql.sh --db-name mydb --db-user myuser --db-password secret123 --import /path/to/dump.sql
# =============================================================================

set -e

# =============================================================================
# Parse arguments
# =============================================================================
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
IMPORT_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --db-name) DB_NAME="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    --import) IMPORT_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: --db-name, --db-user, and --db-password are all required"
  echo "Usage: bash setup-mysql.sh --db-name mydb --db-user myuser --db-password secret"
  exit 1
fi

echo "============================================="
echo " 🗄️  Shipyard - MySQL Setup"
echo "============================================="
echo " Database: $DB_NAME"
echo " User:     $DB_USER"
echo " Import:   ${IMPORT_FILE:-none}"
echo "============================================="
echo ""

# =============================================================================
# Install MySQL
# =============================================================================
echo "📦 Installing MySQL..."
if command -v mysql &> /dev/null; then
  echo "  MySQL already installed"
else
  apt update
  apt install -y mysql-server
  systemctl enable mysql
  systemctl start mysql
  echo "  MySQL installed and started"
fi

# =============================================================================
# Create database and user
# =============================================================================
echo "🔧 Creating database and user..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

echo "  ✅ Database '$DB_NAME' and user '$DB_USER' created"

# =============================================================================
# Import SQL dump (optional)
# =============================================================================
if [ -n "$IMPORT_FILE" ]; then
  if [ -f "$IMPORT_FILE" ]; then
    echo "📥 Importing $IMPORT_FILE..."
    mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$IMPORT_FILE"
    echo "  ✅ Import complete"
  else
    echo "  ⚠️  Import file not found: $IMPORT_FILE"
  fi
fi

echo ""
echo "============================================="
echo " ✅ MySQL Setup Complete!"
echo "============================================="
echo ""
echo " Connection details:"
echo "   Host:     localhost"
echo "   Port:     3306"
echo "   Database: $DB_NAME"
echo "   User:     $DB_USER"
echo ""
echo " JDBC URL:"
echo "   jdbc:mysql://localhost:3306/$DB_NAME?createDatabaseIfNotExist=true"
echo ""
echo " Docker env vars to pass:"
echo "   SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/$DB_NAME?createDatabaseIfNotExist=true"
echo "   SPRING_DATASOURCE_USERNAME=$DB_USER"
echo "   SPRING_DATASOURCE_PASSWORD=<your_password>"
echo ""
