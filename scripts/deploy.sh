#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE="${1:?Usage: deploy.sh IMAGE BUILD_ID [SIMULATE_FAILURE]}"
BUILD_ID="${2:?Build ID is required}"
SIMULATE_FAILURE="${3:-false}"
APP_DIR="/opt/bluegreen"
UPSTREAM_FILE="/etc/nginx/conf.d/active-upstream.conf"
PREVIOUS_FILE="$APP_DIR/previous-port"
CURRENT_FILE="$APP_DIR/current-port"
mkdir -p "$APP_DIR"
if [ ! -s "$UPSTREAM_FILE" ]; then echo "server 127.0.0.1:5001 max_fails=3 fail_timeout=10s;" > "$UPSTREAM_FILE"; fi
CURRENT_PORT="$(grep -oE '127\.0\.0\.1:500[12]' "$UPSTREAM_FILE" | head -1 | awk -F: '{print $2}' || true)"
CURRENT_PORT="${CURRENT_PORT:-5001}"
CURRENT_CONTAINER="bluegreen-$CURRENT_PORT"
if docker ps --format '{{.Names}}' | grep -qx "$CURRENT_CONTAINER"; then
  [ "$CURRENT_PORT" = "5001" ] && NEW_PORT=5002 || NEW_PORT=5001
  HAD_ACTIVE=true
else
  NEW_PORT="$CURRENT_PORT"; HAD_ACTIVE=false
fi
NEW_CONTAINER="bluegreen-$NEW_PORT"
BACKUP_FILE="$APP_DIR/upstream-before-$BUILD_ID.conf"
cp "$UPSTREAM_FILE" "$BACKUP_FILE"
restore_on_failure() {
  echo "Candidate deployment failed; restoring previous Nginx upstream."
  cp "$BACKUP_FILE" "$UPSTREAM_FILE"
  nginx -t && systemctl reload nginx || true
  docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true
}
trap restore_on_failure ERR
docker pull "$IMAGE"
docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true
FAIL_FLAG=false
[ "$SIMULATE_FAILURE" = "true" ] && FAIL_FLAG=true
docker run -d --restart unless-stopped --name "$NEW_CONTAINER" -e FAIL_HEALTH_CHECK="$FAIL_FLAG" -p "127.0.0.1:$NEW_PORT:5000" "$IMAGE"
HEALTHY=false
for ((i=1; i<=15; i++)); do
  if curl --fail --silent --max-time 3 "http://127.0.0.1:$NEW_PORT/health" >/dev/null; then HEALTHY=true; break; fi
  sleep 2
done
[ "$HEALTHY" = "true" ] || { echo "Candidate health check failed"; false; }
if [ "$HAD_ACTIVE" = "true" ]; then echo "$CURRENT_PORT" > "$PREVIOUS_FILE"; fi
echo "server 127.0.0.1:$NEW_PORT max_fails=3 fail_timeout=10s;" > "$UPSTREAM_FILE"
nginx -t
systemctl reload nginx
curl --fail --silent --show-error --max-time 5 http://127.0.0.1/health
echo "$NEW_PORT" > "$CURRENT_FILE"
trap - ERR
echo "Deployment successful: $IMAGE on port $NEW_PORT"
[ "$HAD_ACTIVE" = "false" ] || echo "Previous container $CURRENT_CONTAINER retained for rollback."
