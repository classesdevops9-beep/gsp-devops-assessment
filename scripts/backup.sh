#!/usr/bin/env bash
# ==============================================================================
# Database Backup Script
# Performs mongodump, encrypts archive with 'age', and uploads to off-site storage.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment configuration if available
if [ -f "${ROOT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

TIMESTAMP="$(date -u +"%Y%m%d_%H%M%SZ")"
BACKUP_DIR="${ROOT_DIR}/backups/local"
OFFSITE_DIR="${ROOT_DIR}/backups/offsite_storage"
mkdir -p "${BACKUP_DIR}" "${OFFSITE_DIR}"

DB_NAME="${APP_MONGO_DB:-conduit}"
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
ROOT_USER="${MONGO_ROOT_USER:-admin}"
ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-admin_secret_pass}"

ARCHIVE_NAME="${DB_NAME}_backup_${TIMESTAMP}.dump.gz"
ENCRYPTED_NAME="${ARCHIVE_NAME}.age"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
ENCRYPTED_PATH="${BACKUP_DIR}/${ENCRYPTED_NAME}"

# Age Public Recipient Key (ensure public key is configured)
AGE_KEY="${AGE_RECIPIENT_KEY:-}"
if [ -z "${AGE_KEY}" ]; then
  if [ -f "${ROOT_DIR}/keys/age.pub" ]; then
    AGE_KEY="$(cat "${ROOT_DIR}/keys/age.pub")"
  else
    echo "⚠️  No AGE_RECIPIENT_KEY set. Generating temporary backup keypair in keys/..."
    mkdir -p "${ROOT_DIR}/keys"
    age-keygen -o "${ROOT_DIR}/keys/age.key" 2>/dev/null
    age-keygen -y "${ROOT_DIR}/keys/age.key" > "${ROOT_DIR}/keys/age.pub"
    AGE_KEY="$(cat "${ROOT_DIR}/keys/age.pub")"
    echo "Generated public key: ${AGE_KEY}"
  fi
fi

echo "======================================================================"
echo " Starting Secure Database Backup: [${DB_NAME}]"
echo " Timestamp: ${TIMESTAMP}"
echo "======================================================================"

# Step 1: Execute mongodump (via docker exec if container is running, or local mongodump)
echo "--> [1/4] Dumping database '${DB_NAME}'..."
if docker ps --format '{{.Names}}' | grep -q "conduit-mongo"; then
  docker exec conduit-mongo mongodump \
    --username "${ROOT_USER}" \
    --password "${ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --db "${DB_NAME}" \
    --archive \
    --gzip > "${ARCHIVE_PATH}"
else
  mongodump \
    --host "${MONGO_HOST}:${MONGO_PORT}" \
    --username "${ROOT_USER}" \
    --password "${ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --db "${DB_NAME}" \
    --archive="${ARCHIVE_PATH}" \
    --gzip
fi

DUMP_SIZE="$(du -h "${ARCHIVE_PATH}" | cut -f1)"
echo "✓ Dump created successfully (${DUMP_SIZE})."

# Step 2: Encrypt with age
echo "--> [2/4] Encrypting dump with age public key (${AGE_KEY:0:15}...)..."
age -r "${AGE_KEY}" -o "${ENCRYPTED_PATH}" "${ARCHIVE_PATH}"
rm -f "${ARCHIVE_PATH}" # Remove plaintext archive immediately
echo "✓ Encryption complete: ${ENCRYPTED_NAME}"

# Step 3: Off-site Upload (Cloudflare R2 or secondary isolated storage)
echo "--> [3/4] Uploading to off-site storage..."
if [ -n "${R2_BUCKET_NAME:-}" ] && [ -n "${R2_ENDPOINT_URL:-}" ] && command -v aws >/dev/null 2>&1; then
  echo "Uploading to Cloudflare R2: s3://${R2_BUCKET_NAME}/backups/${ENCRYPTED_NAME}..."
  aws s3 cp "${ENCRYPTED_PATH}" "s3://${R2_BUCKET_NAME}/backups/${ENCRYPTED_NAME}" \
    --endpoint-url "${R2_ENDPOINT_URL}"
else
  echo "Copying to offsite replicated directory: ${OFFSITE_DIR}/${ENCRYPTED_NAME}..."
  cp "${ENCRYPTED_PATH}" "${OFFSITE_DIR}/${ENCRYPTED_NAME}"
fi
echo "✓ Offsite upload complete."

# Step 4: Record metadata
METADATA_FILE="${BACKUP_DIR}/latest_backup.meta"
cat <<EOF > "${METADATA_FILE}"
TIMESTAMP=${TIMESTAMP}
FILENAME=${ENCRYPTED_NAME}
SIZE=$(du -h "${ENCRYPTED_PATH}" | cut -f1)
SHA256=$(shasum -a 256 "${ENCRYPTED_PATH}" | cut -d' ' -f1)
DATABASE=${DB_NAME}
EOF

echo "======================================================================"
echo " Backup finished successfully!"
echo " Encrypted Archive: ${ENCRYPTED_PATH}"
echo " SHA256: $(shasum -a 256 "${ENCRYPTED_PATH}" | cut -d' ' -f1)"
echo "======================================================================"

