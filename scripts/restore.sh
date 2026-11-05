#!/usr/bin/env bash
# ==============================================================================
# Database Restore Script (Disaster Recovery)
# Downloads, decrypts with 'age' private key, runs mongorestore, and checks health.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment configuration
if [ -f "${ROOT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

BACKUP_FILE="${1:-}"
PRIVATE_KEY="${AGE_SECRET_KEY_FILE:-${ROOT_DIR}/keys/age.key}"
DB_NAME="${APP_MONGO_DB:-conduit}"
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
ROOT_USER="${MONGO_ROOT_USER:-admin}"
ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-admin_secret_pass}"

START_TIME=$(date +%s%N 2>/dev/null || date +%s)

echo "======================================================================"
echo " Starting Disaster Recovery Database Restore: [${DB_NAME}]"
echo "======================================================================"

# Determine backup file if not passed
if [ -z "${BACKUP_FILE}" ]; then
  if [ -f "${ROOT_DIR}/backups/local/latest_backup.meta" ]; then
    LATEST_NAME=$(grep "FILENAME=" "${ROOT_DIR}/backups/local/latest_backup.meta" | cut -d'=' -f2)
    BACKUP_FILE="${ROOT_DIR}/backups/local/${LATEST_NAME}"
  else
    # Find latest .age file in backups/
    BACKUP_FILE=$(find "${ROOT_DIR}/backups" -name "*.age" | sort -r | head -n1 || true)
  fi
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
  echo "❌ ERROR: No encrypted backup file found to restore!"
  exit 1
fi

if [ ! -f "${PRIVATE_KEY}" ]; then
  echo "❌ ERROR: Private age decryption key not found at: ${PRIVATE_KEY}"
  echo "Restore requires the age private key."
  exit 1
fi

TMP_RESTORE_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_RESTORE_DIR}"' EXIT

DECRYPTED_PATH="${TMP_RESTORE_DIR}/restored_${DB_NAME}.dump.gz"

# Step 1: Decrypt with age
echo "--> [1/3] Decrypting ${BACKUP_FILE} with age private key..."
age -d -i "${PRIVATE_KEY}" -o "${DECRYPTED_PATH}" "${BACKUP_FILE}"
echo "✓ Archive decrypted successfully."

# Step 2: Execute mongorestore
echo "--> [2/3] Restoring database '${DB_NAME}' via mongorestore (--drop)..."
if docker ps --format '{{.Names}}' | grep -q "conduit-mongo"; then
  cat "${DECRYPTED_PATH}" | docker exec -i conduit-mongo mongorestore \
    --username "${ROOT_USER}" \
    --password "${ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --nsInclude="${DB_NAME}.*" \
    --drop \
    --archive \
    --gzip
else
  mongorestore \
    --host "${MONGO_HOST}:${MONGO_PORT}" \
    --username "${ROOT_USER}" \
    --password "${ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --nsInclude="${DB_NAME}.*" \
    --drop \
    --archive="${DECRYPTED_PATH}" \
    --gzip
fi
echo "✓ mongorestore completed."

# Step 3: Verify Application Health
echo "--> [3/3] Verifying application /health endpoint..."
HEALTH_URL="${HEALTH_CHECK_URL:-http://localhost:8080/health}"
sleep 2

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" || echo "000")
if [ "${HTTP_CODE}" = "200" ]; then
  echo "✓ Application health probe SUCCESS (HTTP 200 OK)."
else
  echo "⚠️  Application returned HTTP ${HTTP_CODE} on ${HEALTH_URL}. Check container status."
fi

END_TIME=$(date +%s%N 2>/dev/null || date +%s)
ELAPSED_SEC=$(echo "scale=2; (${END_TIME} - ${START_TIME}) / 1000000000" | bc 2>/dev/null || echo "N/A")

echo "======================================================================"
echo " Database Restore Drill Completed Successfully!"
echo " Restored From: $(basename "${BACKUP_FILE}")"
echo " Measured Recovery Time Objective (RTO): ${ELAPSED_SEC} seconds"
echo "======================================================================"

