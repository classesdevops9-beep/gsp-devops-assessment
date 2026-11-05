#!/usr/bin/env bash
# ==============================================================================
# Automated Rollback Script
# Redeploys a previous known-healthy image tag using the rolling deployer.
# ==============================================================================
set -euo pipefail

PREV_TAG="${1:-}"

if [ -z "$PREV_TAG" ]; then
  echo "Usage: $0 <previous_image_tag>"
  echo "Example: $0 v1.0.0"
  exit 1
fi

echo "======================================================================"
echo " 🚨 INITIATING EMERGENCY ROLLBACK TO PREVIOUS TAG: ${PREV_TAG}"
echo "======================================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/deploy.sh" "${PREV_TAG}"

echo "✓ Rollback to ${PREV_TAG} completed successfully."

