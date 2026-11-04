```bash
#!/usr/bin/env bash

set -Eeuo pipefail

# --------------------------------------------------
# 1. Deployment variables
# --------------------------------------------------

IMAGE="${1:?Usage: deploy.sh IMAGE BUILD_ID [SIMULATE_FAILURE]}"
BUILD_ID="${2:?Build ID is required}"
SIMULATE_FAILURE="${3:-false}"

APP_DIR="/opt/bluegreen"
UPSTREAM_FILE="/etc/nginx/active-upstream.inc"

CURRENT_FILE="$APP_DIR/current-port"
PREVIOUS_FILE="$APP_DIR/previous-port"

BACKUP_FILE="$APP_DIR/upstream-before-$BUILD_ID.conf"

# Validate build ID
if [[ ! "$BUILD_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: Invalid build ID"
    exit 1
fi

if [[ "$SIMULATE_FAILURE" != "true" && "$SIMULATE_FAILURE" != "false" ]]; then
    echo "ERROR: SIMULATE_FAILURE must be true or false"
    exit 1
fi

mkdir -p "$APP_DIR"

echo "=========================================="
echo "ZERO-DOWNTIME BLUE-GREEN DEPLOYMENT"
echo "=========================================="
echo "Image: $IMAGE"
echo "Build ID: $BUILD_ID"
echo "Simulate failure: $SIMULATE_FAILURE"

# --------------------------------------------------
# 2. Validate Nginx configuration files
# --------------------------------------------------

if [[ ! -f "$UPSTREAM_FILE" ]]; then
    echo "ERROR: Nginx upstream file not found: $UPSTREAM_FILE"
    exit 1
fi

if [[ ! -f /etc/nginx/conf.d/default.conf ]]; then
    echo "ERROR: Nginx default.conf not found"
    exit 1
fi

# --------------------------------------------------
# 3. Identify currently active application
# --------------------------------------------------

CURRENT_PORT="$(
    grep -oE '127\.0\.0\.1:500[12]' "$UPSTREAM_FILE" |
    head -n 1 |
    cut -d ':' -f 2 || true
)"

CURRENT_PORT="${CURRENT_PORT:-5001}"

if [[ "$CURRENT_PORT" != "5001" && "$CURRENT_PORT" != "5002" ]]; then
    echo "ERROR: Invalid active application port: $CURRENT_PORT"
    exit 1
fi

CURRENT_CONTAINER="bluegreen-$CURRENT_PORT"

if docker ps --format '{{.Names}}' | grep -Fxq "$CURRENT_CONTAINER"; then

    HAD_ACTIVE=true

    if [[ "$CURRENT_PORT" == "5001" ]]; then
        NEW_PORT=5002
    else
        NEW_PORT=5001
    fi

else

    HAD_ACTIVE=false
    NEW_PORT="$CURRENT_PORT"

fi

NEW_CONTAINER="bluegreen-$NEW_PORT"

echo "Current port: $CURRENT_PORT"
echo "Candidate port: $NEW_PORT"
echo "Previous application running: $HAD_ACTIVE"

# --------------------------------------------------
# 4. Backup existing Nginx configuration
# --------------------------------------------------

cp "$UPSTREAM_FILE" "$BACKUP_FILE"

CANDIDATE_STARTED=false
DEPLOY_SUCCESS=false

# --------------------------------------------------
# 5. Automatic rollback function
# --------------------------------------------------

rollback_on_error() {

    EXIT_CODE=$?

    trap - ERR

    if [[ "$DEPLOY_SUCCESS" != "true" ]]; then

        echo ""
        echo "=========================================="
        echo "DEPLOYMENT FAILED - STARTING ROLLBACK"
        echo "=========================================="

        if [[ -f "$BACKUP_FILE" ]]; then

            cp "$BACKUP_FILE" "$UPSTREAM_FILE"

            if nginx -t; then
                systemctl reload nginx
                echo "Previous Nginx configuration restored."
            else
                echo "WARNING: Nginx configuration validation failed during rollback."
            fi

        fi

        if [[ "$CANDIDATE_STARTED" == "true" ]]; then

            docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true

            echo "Failed candidate container removed: $NEW_CONTAINER"

        fi

        if [[ "$HAD_ACTIVE" == "true" ]]; then
            echo "Previous application retained: $CURRENT_CONTAINER"
        else
            echo "No previous working application existed."
        fi

        echo "Rollback procedure completed."

    fi

    exit "$EXIT_CODE"
}

trap rollback_on_error ERR

# --------------------------------------------------
# 6. Pull new Docker image
# --------------------------------------------------

echo ""
echo "Pulling candidate Docker image..."

docker pull "$IMAGE"

# --------------------------------------------------
# 7. Remove stale candidate container if present
# --------------------------------------------------

echo "Preparing candidate container..."

docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true

# --------------------------------------------------
# 8. Configure simulated failure
# --------------------------------------------------

FAIL_FLAG=false

if [[ "$SIMULATE_FAILURE" == "true" ]]; then
    FAIL_FLAG=true
    echo "SIMULATION ENABLED: Candidate health check will fail."
fi

# --------------------------------------------------
# 9. Start candidate container
# --------------------------------------------------

echo ""
echo "Starting candidate application..."

docker run -d \
    --restart unless-stopped \
    --name "$NEW_CONTAINER" \
    -e FAIL_HEALTH_CHECK="$FAIL_FLAG" \
    -p "127.0.0.1:$NEW_PORT:5000" \
    "$IMAGE"

CANDIDATE_STARTED=true

echo "Candidate container started: $NEW_CONTAINER"

# --------------------------------------------------
# 10. Candidate health check
# --------------------------------------------------

echo ""
echo "Checking candidate application health..."

HEALTHY=false

for ((i=1; i<=15; i++)); do

    if curl --fail --silent --max-time 3 \
        "http://127.0.0.1:$NEW_PORT/health" >/dev/null; then

        HEALTHY=true
        echo "Candidate health check passed."
        break

    fi

    echo "Health check attempt $i failed."

    sleep 2

done

if [[ "$HEALTHY" != "true" ]]; then
    echo "ERROR: Candidate application is unhealthy."
    exit 1
fi

# --------------------------------------------------
# 11. Switch Nginx traffic to candidate
# --------------------------------------------------

echo ""
echo "Switching Nginx traffic..."

printf 'server 127.0.0.1:%s max_fails=3 fail_timeout=10s;\n' \
    "$NEW_PORT" > "$UPSTREAM_FILE"

nginx -t

systemctl reload nginx

echo "Nginx traffic switched to port $NEW_PORT"

# --------------------------------------------------
# 12. Verify application through Nginx
# --------------------------------------------------

echo ""
echo "Verifying application through Nginx..."

curl --fail --silent --show-error --max-time 5 \
    http://127.0.0.1/health

echo ""

curl --fail --silent --show-error --max-time 5 \
    http://127.0.0.1/

echo ""

echo "Nginx application verification passed."

# --------------------------------------------------
# 13. Record successful deployment
# --------------------------------------------------

if [[ "$HAD_ACTIVE" == "true" ]]; then
    echo "$CURRENT_PORT" > "$PREVIOUS_FILE"
fi

echo "$NEW_PORT" > "$CURRENT_FILE"

# --------------------------------------------------
# 14. Mark deployment successful
# --------------------------------------------------

DEPLOY_SUCCESS=true

trap - ERR

echo ""
echo "=========================================="
echo "DEPLOYMENT SUCCESSFUL"
echo "=========================================="

echo "Docker image: $IMAGE"
echo "Active port: $NEW_PORT"
echo "Active container: $NEW_CONTAINER"

if [[ "$HAD_ACTIVE" == "true" ]]; then
    echo "Previous container retained: $CURRENT_CONTAINER"
    echo "Previous port: $CURRENT_PORT"
    echo "Previous port recorded in: $PREVIOUS_FILE"
else
    echo "This was the initial deployment."
fi

echo "Current port recorded in: $CURRENT_FILE"

echo "=========================================="
```
