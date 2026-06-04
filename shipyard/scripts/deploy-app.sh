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
echo "$DROPLET_SSH_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY_FILE"

# =============================================================================
# Build docker run command
# =============================================================================
DOCKER_RUN="docker run -d --name $APP_NAME"

# Network configuration
if [ "$NETWORK_MODE" = "host" ]; then
  DOCKER_RUN="$DOCKER_RUN --network host"
else
  DOCKER_RUN="$DOCKER_RUN -p $HOST_PORT:$APP_PORT"
fi

# Environment variables
if [ -n "$ENV_VARS" ]; then
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      DOCKER_RUN="$DOCKER_RUN -e \"$line\""
    fi
  done <<< "$ENV_VARS"
fi

# Additional docker args
if [ -n "$DOCKER_ARGS" ]; then
  DOCKER_RUN="$DOCKER_RUN $DOCKER_ARGS"
fi

# Restart policy and image
DOCKER_RUN="$DOCKER_RUN --restart unless-stopped $IMAGE"

# =============================================================================
# Build image name for cleanup (without tag)
# =============================================================================
IMAGE_BASE="${IMAGE%:*}"

# =============================================================================
# Deploy via SSH
# =============================================================================
echo ""
echo "🔐 Connecting to $DROPLET_HOST..."

ssh $SSH_OPTS root@"$DROPLET_HOST" <<DEPLOY_SCRIPT
set -e

echo "📦 Logging in to registry..."
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USER" --password-stdin

echo "⬇️  Pulling $IMAGE..."
docker pull $IMAGE

echo "🔄 Stopping old container..."
docker stop $APP_NAME 2>/dev/null || true
docker rm $APP_NAME 2>/dev/null || true

echo "🚀 Starting new container..."
$DOCKER_RUN

echo "🧹 Cleaning up old images..."
docker images $IMAGE_BASE --format '{{.Repository}}:{{.Tag}}' \
  | grep -v '<none>' \
  | grep -v ':latest' \
  | sort -t: -k2 -V -r \
  | tail -n +$KEEP_IMAGES \
  | xargs -r docker rmi 2>/dev/null || true
docker image prune -f 2>/dev/null || true

echo ""
echo "✅ $APP_NAME deployed successfully!"
echo "   Container: \$(docker ps --filter name=$APP_NAME --format '{{.Status}}')"
DEPLOY_SCRIPT

# =============================================================================
# Cleanup
# =============================================================================
rm -f "$SSH_KEY_FILE"

echo ""
echo "============================================="
echo " ✅ Deployment complete!"
echo "============================================="
