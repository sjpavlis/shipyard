#!/bin/bash
# =============================================================================
# Shipyard - Deploy Application
# =============================================================================
# Pulls the latest Docker image and restarts the container on the VPS.
# Designed to run in GitHub Actions or locally.
#
# Required environment variables:
#   APP_NAME        - Container name (e.g. "patrices", "intsda")
#   IMAGE           - Full image path (e.g. "ghcr.io/user/app:latest")
#   DROPLET_HOST    - VPS IP address
#   DROPLET_SSH_KEY - SSH private key (multiline)
#   REGISTRY_TOKEN  - Token to authenticate with container registry
#   REGISTRY_USER   - Registry username
#
# Optional environment variables:
#   APP_PORT        - Application port (default: 8080)
#   HOST_PORT       - Host port to map to (default: same as APP_PORT)
#   NETWORK_MODE    - Docker network mode: "bridge" or "host" (default: bridge)
#   ENV_VARS        - Environment variables to pass (newline-separated KEY=VALUE)
#   KEEP_IMAGES     - Number of old images to retain (default: 3)
#   DOCKER_ARGS     - Additional docker run arguments
#
# Usage (in GitHub Actions):
#   - name: Deploy
#     run: .shipyard/scripts/deploy-app.sh
#     env:
#       APP_NAME: myapp
#       IMAGE: ghcr.io/user/app:latest
#       DROPLET_HOST: ${{ secrets.DROPLET_HOST }}
#       DROPLET_SSH_KEY: ${{ secrets.DROPLET_SSH_KEY }}
#       REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
#       REGISTRY_USER: ${{ github.actor }}
# =============================================================================

set -e

# =============================================================================
# Validate required variables
# =============================================================================
REQUIRED_VARS=(APP_NAME IMAGE DROPLET_HOST DROPLET_SSH_KEY REGISTRY_TOKEN REGISTRY_USER)
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Error: $var is required but not set"
    exit 1
  fi
done

# =============================================================================
# Set defaults
# =============================================================================
APP_PORT="${APP_PORT:-8080}"
HOST_PORT="${HOST_PORT:-$APP_PORT}"
NETWORK_MODE="${NETWORK_MODE:-bridge}"
KEEP_IMAGES="${KEEP_IMAGES:-3}"
DOCKER_ARGS="${DOCKER_ARGS:-}"

echo "============================================="
echo " 🚢 Shipyard - Deploying $APP_NAME"
echo "============================================="
echo " Image:    $IMAGE"
echo " Host:     $DROPLET_HOST"
echo " Port:     $HOST_PORT:$APP_PORT"
echo " Network:  $NETWORK_MODE"
echo "============================================="

# =============================================================================
# Setup SSH key
# =============================================================================
SSH_KEY_FILE=$(mktemp)
printf '%s\n' "$DROPLET_SSH_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY_FILE"

# =============================================================================
# Build the remote deploy script locally, then send it
# =============================================================================
# Using a script file avoids heredoc variable expansion issues and special
# character problems with JDBC URLs, passwords, etc.

REMOTE_SCRIPT=$(mktemp)

cat > "$REMOTE_SCRIPT" <<'SCRIPT_HEADER'
#!/bin/bash
set -e
SCRIPT_HEADER

# Registry login
cat >> "$REMOTE_SCRIPT" <<EOF
echo "📦 Logging in to registry..."
echo '${REGISTRY_TOKEN}' | docker login ghcr.io -u '${REGISTRY_USER}' --password-stdin

echo "⬇️  Pulling ${IMAGE}..."
docker pull ${IMAGE}

echo "🔄 Stopping old container..."
docker stop ${APP_NAME} 2>/dev/null || true
docker rm ${APP_NAME} 2>/dev/null || true

echo "🚀 Starting new container..."
EOF

# Build docker run command
DOCKER_CMD="docker run -d --name ${APP_NAME}"

# Network configuration
if [ "$NETWORK_MODE" = "host" ]; then
  DOCKER_CMD="$DOCKER_CMD --network host"
else
  DOCKER_CMD="$DOCKER_CMD -p ${HOST_PORT}:${APP_PORT}"
fi

# Environment variables - each one gets its own -e flag with single quotes
# This safely handles special characters in values (?, =, &, etc.)
if [ -n "$ENV_VARS" ]; then
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      # Extract key and value separately to handle special chars
      ENV_KEY="${line%%=*}"
      ENV_VAL="${line#*=}"
      DOCKER_CMD="$DOCKER_CMD -e ${ENV_KEY}='${ENV_VAL}'"
    fi
  done <<< "$ENV_VARS"
fi

# Additional docker args
if [ -n "$DOCKER_ARGS" ]; then
  DOCKER_CMD="$DOCKER_CMD $DOCKER_ARGS"
fi

# Restart policy and image
DOCKER_CMD="$DOCKER_CMD --restart unless-stopped ${IMAGE}"

# Write the docker run command to the script
echo "$DOCKER_CMD" >> "$REMOTE_SCRIPT"

# Image cleanup
cat >> "$REMOTE_SCRIPT" <<EOF

echo "🧹 Cleaning up old images..."
docker images ${IMAGE%:*} --format '{{.Repository}}:{{.Tag}}' \\
  | grep -v '<none>' \\
  | grep -v ':latest' \\
  | sort -t: -k2 -V -r \\
  | tail -n +${KEEP_IMAGES} \\
  | xargs -r docker rmi 2>/dev/null || true
docker image prune -f 2>/dev/null || true

echo ""
echo "✅ ${APP_NAME} deployed successfully!"
docker ps --filter name=${APP_NAME} --format 'Container: {{.Status}}'
EOF

# =============================================================================
# Deploy: copy script to remote and execute
# =============================================================================
echo ""
echo "🔐 Connecting to $DROPLET_HOST..."

# Copy the script to the remote server
scp $SSH_OPTS "$REMOTE_SCRIPT" root@"$DROPLET_HOST":/tmp/shipyard-deploy.sh

# Execute it
ssh $SSH_OPTS root@"$DROPLET_HOST" "chmod +x /tmp/shipyard-deploy.sh && /tmp/shipyard-deploy.sh && rm -f /tmp/shipyard-deploy.sh"

# =============================================================================
# Cleanup local temp files
# =============================================================================
rm -f "$SSH_KEY_FILE"
rm -f "$REMOTE_SCRIPT"

echo ""
echo "============================================="
echo " ✅ Deployment complete!"
echo "============================================="
