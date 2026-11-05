#!/usr/bin/env bash
# ==============================================================================
# Health Monitoring & Webhook Alerting Daemon / Cron Script
# Probes /health endpoint and dispatches Slack/Discord alerts on failure.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment configuration
if [ -f "${ROOT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

HEALTH_URL="${HEALTH_CHECK_URL:-http://localhost:8080/health}"
WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
HOSTNAME_VAL="$(hostname)"
TIMESTAMP="$(date -u +"%Y-%m-%d %H:%M:%SZ")"
TEST_MODE="${1:-}"

send_alert() {
  local error_reason="$1"
  local details="$2"

  echo "🚨 [ALERT TRIGGERED] ${error_reason}: ${details}"

  if [ -z "${WEBHOOK_URL}" ] || [ "${WEBHOOK_URL}" = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" ]; then
    echo "⚠️  ALERT_WEBHOOK_URL not configured. Simulating alert payload output:"
    cat <<EOF
----------------------------------------------------------------------
[SIMULATED WEBHOOK NOTIFICATION]
To: Slack/Discord Operations Channel
Timestamp: ${TIMESTAMP}
Environment: Production (Host: ${HOSTNAME_VAL})
Severity: CRITICAL
Message: 🚨 Study Now Application Outage Detected!
Reason: ${error_reason}
Details: ${details}
Action Required: Follow 2AM On-Call Runbook immediately.
----------------------------------------------------------------------
EOF
    return 0
  fi

  # Build JSON payload (Slack & Discord compatible)
  local payload
  if [[ "${WEBHOOK_URL}" == *"discord"* ]]; then
    payload=$(cat <<EOF
{
  "content": "🚨 **CRITICAL ALERT: Study Now API Down**\n- **Host**: \`${HOSTNAME_VAL}\`\n- **Time**: \`${TIMESTAMP}\`\n- **Error**: ${error_reason}\n- **Details**: \`${details}\`\n- **Runbook**: See README.md (Site Down at 2AM)"
}
EOF
)
  else
    payload=$(cat <<EOF
{
  "text": "🚨 *CRITICAL ALERT: Study Now API Down*",
  "attachments": [
    {
      "color": "#FF0000",
      "fields": [
        {"title": "Host", "value": "${HOSTNAME_VAL}", "short": true},
        {"title": "Timestamp", "value": "${TIMESTAMP}", "short": true},
        {"title": "Failure Reason", "value": "${error_reason}", "short": false},
        {"title": "Details", "value": "${details}", "short": false},
        {"title": "Action", "value": "Consult 2AM Outage Runbook in repository README", "short": false}
      ]
    }
  ]
}
EOF
)
  fi

  curl -s -X POST -H 'Content-type: application/json' --data "${payload}" "${WEBHOOK_URL}" >/dev/null || true
  echo "✓ Webhook alert sent to channel."
}

if [ "${TEST_MODE}" = "--test-alert" ]; then
  echo "Triggering test alert simulation..."
  send_alert "Manual Test Drill" "Simulated failure requested via --test-alert flag"
  exit 0
fi

# Execute probe
RESPONSE_RAW=$(curl -s -w "\n%{http_code}" --connect-timeout 3 --max-time 5 "${HEALTH_URL}" || echo -e '{"status":"UNREACHABLE"}\n000')
HTTP_CODE=$(echo "${RESPONSE_RAW}" | tail -n1)
BODY=$(echo "${RESPONSE_RAW}" | sed '$d')

if [ "${HTTP_CODE}" != "200" ]; then
  send_alert "HTTP Status ${HTTP_CODE} Non-Healthy" "Endpoint ${HEALTH_URL} returned code ${HTTP_CODE}. Response body: ${BODY}"
  exit 1
fi

# Validate JSON content
if ! echo "${BODY}" | grep -q '"status":"UP"'; then
  send_alert "Degraded Service Health" "Response body did not report status UP: ${BODY}"
  exit 1
fi

echo "✓ Health check PASSED at ${TIMESTAMP} (HTTP ${HTTP_CODE} - ${BODY})"
exit 0
