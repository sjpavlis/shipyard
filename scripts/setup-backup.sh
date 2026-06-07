#!/bin/bash
# =============================================================================
# Shipyard - Database Backup Setup
# =============================================================================
# Configures automated daily MySQL backups that push to a GitHub repository.
#
# Usage:
#   bash setup-backup.sh \
#     --repo-url https://user:token@github.com/user/repo.git \
#     --repo-dir /root/myapp-repo \
#     --db-name mydb \
#     --db-user myuser \
#     --db-password secret \
#     --backup-path backups/mydb.sql \
#     --cron-hour 2
# =============================================================================

set -e

# =============================================================================
# Parse arguments
# =============================================================================
REPO_URL=""
REPO_DIR=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
BACKUP_PATH="backups/database.sql"
CRON_HOUR=2

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --db-name) DB_NAME="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    --backup-path) BACKUP_PATH="$2"; shift 2 ;;
    --cron-hour) CRON_HOUR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$REPO_URL" ] || [ -z "$REPO_DIR" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: All of --repo-url, --repo-dir, --db-name, --db-user, --db-password are required"
  exit 1
fi

echo "============================================="
echo " 💾 Shipyard - Backup Setup"
echo "============================================="
echo " Database:    $DB_NAME"
echo " Repo:        $REPO_DIR"
echo " Backup path: $BACKUP_PATH"
echo " Schedule:    Daily at ${CRON_HOUR}:00 AM"
echo "============================================="
echo ""

# =============================================================================
# Clone repo if not exists
# =============================================================================
if [ ! -d "$REPO_DIR" ]; then
  echo "📥 Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
  git config user.name "shipyard-backup"
  git config user.email "backup@shipyard"
else
  echo "📂 Repository already exists at $REPO_DIR"
fi

# =============================================================================
# Create backup script
# =============================================================================
BACKUP_SCRIPT="$REPO_DIR/scripts/backup-db.sh"
mkdir -p "$(dirname "$BACKUP_SCRIPT")"
mkdir -p "$REPO_DIR/$(dirname "$BACKUP_PATH")"

# Use a quoted heredoc (<<'EOF') to prevent variable expansion,
# then replace placeholders. This safely handles special chars in passwords.
cat > "$BACKUP_SCRIPT" <<SCRIPT
#!/bin/bash
cd '$REPO_DIR'
git pull --rebase
mysqldump -u '$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' > '$BACKUP_PATH'
git add '$BACKUP_PATH'
git commit -m "[auto-update] backup: db dump \$(date +%Y-%m-%d)" --allow-empty
git push
SCRIPT

chmod +x "$BACKUP_SCRIPT"
echo "✅ Backup script created at $BACKUP_SCRIPT"

# =============================================================================
# Setup cron job
# =============================================================================
CRON_JOB="0 $CRON_HOUR * * * $BACKUP_SCRIPT"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
  echo "⚠️  Cron job already exists"
else
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  echo "✅ Cron job added: runs daily at ${CRON_HOUR}:00 AM"
fi

echo ""
echo "============================================="
echo " ✅ Backup Setup Complete!"
echo "============================================="
echo ""
echo " The database will be dumped daily at ${CRON_HOUR}:00 AM"
echo " and pushed to your repository at: $BACKUP_PATH"
echo ""
echo " To test manually:"
echo "   bash $BACKUP_SCRIPT"
echo ""
