#!/usr/bin/env bash
set -euo pipefail

: "${APP_MONGO_USER:?APP_MONGO_USER must be set}"
: "${APP_MONGO_PASSWORD:?APP_MONGO_PASSWORD must be set}"
: "${APP_MONGO_DB:?APP_MONGO_DB must be set}"

json_quote() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\b'/\\b}
  value=${value//$'\f'/\\f}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

APP_MONGO_USER_JSON="$(json_quote "$APP_MONGO_USER")"
APP_MONGO_PASSWORD_JSON="$(json_quote "$APP_MONGO_PASSWORD")"
APP_MONGO_DB_JSON="$(json_quote "$APP_MONGO_DB")"

echo "[INIT-MONGO] Creating least-privilege user '${APP_MONGO_USER}' on database '${APP_MONGO_DB}'..."

mongosh --quiet "$APP_MONGO_DB" <<EOF
db.createUser({
  user: ${APP_MONGO_USER_JSON},
  pwd: ${APP_MONGO_PASSWORD_JSON},
  roles: [{ role: 'readWrite', db: ${APP_MONGO_DB_JSON} }]
});
EOF

echo "[INIT-MONGO] User '${APP_MONGO_USER}' created with [readWrite] role on '${APP_MONGO_DB}'."
