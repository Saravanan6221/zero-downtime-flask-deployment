#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="/opt/bluegreen"
UPSTREAM_FILE="/etc/nginx/conf.d/active-upstream.conf"
PREVIOUS_FILE="$APP_DIR/previous-port"
[ -s "$PREVIOUS_FILE" ] || { echo "No previous deployment is recorded."; exit 1; }
PREVIOUS_PORT="$(cat "$PREVIOUS_FILE")"
[[ "$PREVIOUS_PORT" == "5001" || "$PREVIOUS_PORT" == "5002" ]] || { echo "Invalid previous port"; exit 1; }
PREVIOUS_CONTAINER="bluegreen-$PREVIOUS_PORT"
docker ps --format '{{.Names}}' | grep -qx "$PREVIOUS_CONTAINER" || { echo "Previous container is not running."; exit 1; }
curl --fail --silent --max-time 3 "http://127.0.0.1:$PREVIOUS_PORT/health" >/dev/null
echo "server 127.0.0.1:$PREVIOUS_PORT max_fails=3 fail_timeout=10s;" > "$UPSTREAM_FILE"
nginx -t
systemctl reload nginx
curl --fail --silent --show-error --max-time 5 http://127.0.0.1/health
echo
echo "Rollback completed. Traffic now points to port $PREVIOUS_PORT."
