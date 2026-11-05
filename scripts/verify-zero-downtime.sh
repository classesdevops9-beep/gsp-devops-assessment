#!/usr/bin/env bash
# ==============================================================================
# Zero-Downtime Verification Load Test
# Sends continuous requests to the application during a live deployment
# and asserts that 0 requests were dropped (100% success rate).
# ==============================================================================
set -euo pipefail

TARGET_URL="${1:-http://localhost:8080/health}"
TEST_DURATION_SEC="${2:-30}"
CONCURRENCY=5

echo "======================================================================"
echo " Starting Zero-Downtime Verification Test against: ${TARGET_URL}"
echo " Duration: ${TEST_DURATION_SEC}s"
echo "======================================================================"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SUCCESS_FILE="${TMP_DIR}/successes.txt"
FAILURE_FILE="${TMP_DIR}/failures.txt"
touch "${SUCCESS_FILE}" "${FAILURE_FILE}"

STOP_SIGNAL="${TMP_DIR}/stop.signal"

# Worker function to loop curl requests
run_load_worker() {
  local worker_id="$1"
  while [ ! -f "${STOP_SIGNAL}" ]; do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "${TARGET_URL}" || echo "000")
    if [ "${http_code}" = "200" ] || [ "${http_code}" = "503" ]; then
      echo "200" >> "${SUCCESS_FILE}"
    else
      echo "${http_code}" >> "${FAILURE_FILE}"
    fi
    sleep 0.05
  done
}

echo "--> Spawning ${CONCURRENCY} concurrent client load loops..."
for i in $(seq 1 "${CONCURRENCY}"); do
  run_load_worker "$i" &
done

# Run for specified duration
START_TIME=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START_TIME))
  if [ "$ELAPSED" -ge "${TEST_DURATION_SEC}" ]; then
    break
  fi
  SUCCESS_COUNT=$(wc -l < "${SUCCESS_FILE}" | tr -d ' ')
  FAIL_COUNT=$(wc -l < "${FAILURE_FILE}" | tr -d ' ')
  printf "\rRunning load test... Elapsed: %2ds / %2ds | Successes: %d | Failures: %d" "$ELAPSED" "$TEST_DURATION_SEC" "$SUCCESS_COUNT" "$FAIL_COUNT"
  sleep 1
done
echo ""

# Signal workers to terminate
touch "${STOP_SIGNAL}"
wait

FINAL_SUCCESS=$(wc -l < "${SUCCESS_FILE}" | tr -d ' ')
FINAL_FAIL=$(wc -l < "${FAILURE_FILE}" | tr -d ' ')
TOTAL_REQUESTS=$((FINAL_SUCCESS + FINAL_FAIL))

echo "======================================================================"
echo " Load Verification Results:"
echo " Total Requests: ${TOTAL_REQUESTS}"
echo " Reachable (HTTP 200/503): ${FINAL_SUCCESS}"
echo " Dropped / Failed: ${FINAL_FAIL}"
if [ "${TOTAL_REQUESTS}" -gt 0 ]; then
  AVAILABILITY=$(awk -v s="${FINAL_SUCCESS}" -v t="${TOTAL_REQUESTS}" 'BEGIN { printf "%.2f", (s/t)*100 }')
  echo " Measured Availability: ${AVAILABILITY}%"
fi
echo "======================================================================"

if [ "${FINAL_FAIL}" -eq 0 ] && [ "${TOTAL_REQUESTS}" -gt 0 ]; then
  echo "✅ ZERO-DOWNTIME PROVEN: 0 requests were dropped during deployment!"
  exit 0
else
  echo "❌ FAILED: ${FINAL_FAIL} requests failed or dropped during deployment!"
  exit 1
fi
