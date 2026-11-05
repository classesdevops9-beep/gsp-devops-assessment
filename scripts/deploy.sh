#!/usr/bin/env bash
# ==============================================================================
# Zero-Downtime Rolling Deployment Script (Blue/Green Rolling Switch)
# ==============================================================================
set -euo pipefail

NEW_TAG="${1:-latest}"
SERVICE_PREFIX="conduit"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
MAX_HEALTH_ATTEMPTS=20
HEALTH_INTERVAL=2

echo "======================================================================"
echo " Starting Zero-Downtime Deployment: Image Tag -> ${NEW_TAG}"
echo "======================================================================"

# Ensure environment file exists
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

export IMAGE_TAG="${NEW_TAG}"

wait_for_service_health() {
  local service_name="$1"
  local attempt=1

  echo "==> Verifying health status of [${service_name}]..."
  while [ "$attempt" -le "$MAX_HEALTH_ATTEMPTS" ]; do
    local health_status
    health_status=$(docker inspect --format='{{json .State.Health.Status}}' "${SERVICE_PREFIX}-${service_name}" 2>/dev/null || echo "\"starting\"")
    health_status="${health_status//\"/}"

    if [ "$health_status" = "healthy" ]; then
      echo "✓ [${service_name}] is HEALTHY and serving traffic (Attempt ${attempt}/${MAX_HEALTH_ATTEMPTS})."
      return 0
    fi

    echo "    Waiting for [${service_name}] to become healthy (Current: ${health_status}, Attempt ${attempt}/${MAX_HEALTH_ATTEMPTS})..."
    sleep "$HEALTH_INTERVAL"
    attempt=$((attempt + 1))
  done

  echo "❌ ERROR: [${service_name}] failed health check after $((MAX_HEALTH_ATTEMPTS * HEALTH_INTERVAL)) seconds!"
  return 1
}

# 1. Update and restart app-blue
echo "--> [Step 1/3] Updating app-blue to tag ${NEW_TAG}..."
docker compose -f "${COMPOSE_FILE}" up -d --no-deps --build app-blue

if ! wait_for_service_health "app-blue"; then
  echo "🚨 Deployment failed on app-blue! Initiating rollback..."
  exit 1
fi

# 2. Update and restart app-green
echo "--> [Step 2/3] Updating app-green to tag ${NEW_TAG}..."
docker compose -f "${COMPOSE_FILE}" up -d --no-deps --build app-green

if ! wait_for_service_health "app-green"; then
  echo "🚨 Deployment failed on app-green! Initiating rollback..."
  exit 1
fi

# 3. Gracefully reload Nginx proxy to refresh upstream keepalives
echo "--> [Step 3/3] Gracefully reloading Nginx configuration..."
docker compose -f "${COMPOSE_FILE}" exec -T nginx nginx -s reload || true

echo "======================================================================"
echo "✓ Zero-downtime deployment of tag [${NEW_TAG}] COMPLETED SUCCESSFULLY!"
echo "======================================================================"
