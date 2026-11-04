
#!/usr/bin/env bash

set -Eeuo pipefail

# ==========================================================
# ZERO-DOWNTIME FLASK DEPLOYMENT
# Docker + Nginx + AWS EC2
# ==========================================================

# Arguments passed by Jenkins
IMAGE="${1:?Usage: deploy.sh IMAGE BUILD_ID [SIMULATE_FAILURE]}"
BUILD_ID="${2:?Build ID is required}"
SIMULATE_FAILURE="${3:-false}"

# Application configuration
APP_DIR="/opt/bluegreen"
UPSTREAM_FILE="/etc/nginx/active-upstream.inc"

CURRENT_FILE="$APP_DIR/current-port"
PREVIOUS_FILE="$APP_DIR/previous-port"

BACKUP_FILE="$APP_DIR/upstream-backup-$BUILD_ID.conf"

# Deployment state
DEPLOY_SUCCESS=false
CANDIDATE_STARTED=false
UPSTREAM_CHANGED=false
HAD_ACTIVE=false

# ==========================================================
# STEP 1: CHECK ROOT PRIVILEGES
# ==========================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script using sudo."
    exit 1
fi

echo "=========================================="
echo "ZERO-DOWNTIME DEPLOYMENT STARTED"
echo "=========================================="

echo "Docker image: $IMAGE"
echo "Build ID: $BUILD_ID"
echo "Simulate failure: $SIMULATE_FAILURE"

# ==========================================================
# STEP 2: CHECK REQUIRED COMMANDS
# ==========================================================

for command in docker nginx curl systemctl grep awk; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command"
        exit 1
    fi
done

# ==========================================================
# STEP 3: PREPARE APPLICATION DIRECTORY
# ==========================================================

mkdir -p "$APP_DIR"

# ==========================================================
# STEP 4: CHECK NGINX UPSTREAM CONFIGURATION
# ==========================================================

if [[ ! -s "$UPSTREAM_FILE" ]]; then
    echo "Creating initial Nginx upstream configuration."

    echo "server 127.0.0.1:5001 max_fails=3 fail_timeout=10s;" \
        > "$UPSTREAM_FILE"
fi

CURRENT_PORT="$(
    grep -oE '127\.0\.0\.1:500[12]' "$UPSTREAM_FILE" |
    head -n 1 |
    awk -F: '{print $2}' || true
)"

if [[ "$CURRENT_PORT" != "5001" && "$CURRENT_PORT" != "5002" ]]; then
    echo "ERROR: Invalid Nginx upstream configuration."
    exit 1
fi

# ==========================================================
# STEP 5: IDENTIFY ACTIVE CONTAINER
# ==========================================================

CURRENT_CONTAINER="bluegreen-$CURRENT_PORT"

if docker ps --format '{{.Names}}' |
    grep -qx "$CURRENT_CONTAINER"; then

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
echo "New deployment port: $NEW_PORT"
echo "Current container: $CURRENT_CONTAINER"
echo "New container: $NEW_CONTAINER"

# ==========================================================
# STEP 6: BACK UP CURRENT NGINX CONFIGURATION
# ==========================================================

cp "$UPSTREAM_FILE" "$BACKUP_FILE"

echo "Nginx upstream backup created: $BACKUP_FILE"

# ==========================================================
# STEP 7: AUTOMATIC ROLLBACK FUNCTION
# ==========================================================

rollback_on_exit() {

    local EXIT_CODE=$?

    trap - EXIT

    if [[ "$DEPLOY_SUCCESS" != "true" ]]; then

        echo ""
        echo "=========================================="
        echo "DEPLOYMENT FAILED - ROLLBACK STARTED"
        echo "=========================================="

        # Restore previous Nginx upstream only
        # if the candidate switch was attempted.

        if [[ "$UPSTREAM_CHANGED" == "true" ]]; then

            if [[ -f "$BACKUP_FILE" ]]; then

                cp "$BACKUP_FILE" "$UPSTREAM_FILE"

                if nginx -t; then
                    systemctl reload nginx
                    echo "Previous Nginx upstream restored."
                else
                    echo "WARNING: Restored Nginx configuration is invalid."
                fi

            fi

        fi

        # Remove failed candidate container.

        if [[ "$CANDIDATE_STARTED" == "true" ]]; then

            docker rm -f "$NEW_CONTAINER" \
                >/dev/null 2>&1 || true

            echo "Failed candidate container removed."

        fi

        echo "=========================================="
        echo "ROLLBACK PROCEDURE FINISHED"
        echo "=========================================="

    fi

    exit "$EXIT_CODE"
}

trap rollback_on_exit EXIT

# ==========================================================
# STEP 8: PULL DOCKER IMAGE
# ==========================================================

echo "Pulling Docker image: $IMAGE"

docker pull "$IMAGE"

# ==========================================================
# STEP 9: REMOVE OLD INACTIVE CANDIDATE
# ==========================================================

echo "Removing any old candidate container."

docker rm -f "$NEW_CONTAINER" \
    >/dev/null 2>&1 || true

# ==========================================================
# STEP 10: START NEW CANDIDATE CONTAINER
# ==========================================================

FAIL_FLAG=false

if [[ "$SIMULATE_FAILURE" == "true" ]]; then
    FAIL_FLAG=true
fi

echo "Starting candidate application."

CANDIDATE_STARTED=true

docker run -d \
    --restart unless-stopped \
    --name "$NEW_CONTAINER" \
    -e FAIL_HEALTH_CHECK="$FAIL_FLAG" \
    -p "127.0.0.1:$NEW_PORT:5000" \
    "$IMAGE"

echo "Candidate container started."

# ==========================================================
# STEP 11: CHECK CANDIDATE APPLICATION HEALTH
# ==========================================================

echo "Checking candidate application health."

HEALTHY=false

for attempt in $(seq 1 20); do

    if curl \
        --fail \
        --silent \
        --max-time 3 \
        "http://127.0.0.1:$NEW_PORT/health" \
        >/dev/null; then

        HEALTHY=true
        echo "Candidate health check successful."
        break

    fi

    echo "Health check attempt $attempt/20 failed."

    sleep 2

done

if [[ "$HEALTHY" != "true" ]]; then

    echo "ERROR: Candidate application is unhealthy."

    exit 1

fi

# ==========================================================
# STEP 12: SAVE PREVIOUS ACTIVE PORT
# ==========================================================

if [[ "$HAD_ACTIVE" == "true" ]]; then

    echo "$CURRENT_PORT" > "$PREVIOUS_FILE"

    echo "Previous active port saved: $CURRENT_PORT"

fi

# ==========================================================
# STEP 13: SWITCH NGINX TO NEW APPLICATION
# ==========================================================

echo "Switching Nginx traffic to candidate."

UPSTREAM_CHANGED=true

echo "server 127.0.0.1:$NEW_PORT max_fails=3 fail_timeout=10s;" \
    > "$UPSTREAM_FILE"

# ==========================================================
# STEP 14: VALIDATE NGINX CONFIGURATION
# ==========================================================

echo "Testing Nginx configuration."

nginx -t

# ==========================================================
# STEP 15: RELOAD NGINX
# ==========================================================

echo "Reloading Nginx."

systemctl reload nginx

# ==========================================================
# STEP 16: VERIFY THROUGH NGINX
# ==========================================================

echo "Verifying application through Nginx."

NGINX_HEALTHY=false

for attempt in $(seq 1 10); do

    if curl \
        --fail \
        --silent \
        --max-time 5 \
        http://127.0.0.1/health \
        >/dev/null; then

        NGINX_HEALTHY=true
        break

    fi

    echo "Nginx health check attempt $attempt/10 failed."

    sleep 2

done

if [[ "$NGINX_HEALTHY" != "true" ]]; then

    echo "ERROR: Nginx health verification failed."

    exit 1

fi

# Verify home page too.

curl \
    --fail \
    --silent \
    --show-error \
    --max-time 5 \
    http://127.0.0.1/

echo ""

# ==========================================================
# STEP 17: SAVE CURRENT DEPLOYMENT STATE
# ==========================================================

echo "$NEW_PORT" > "$CURRENT_FILE"

# ==========================================================
# STEP 18: MARK DEPLOYMENT SUCCESSFUL
# ==========================================================

DEPLOY_SUCCESS=true

echo "=========================================="
echo "ZERO-DOWNTIME DEPLOYMENT SUCCESSFUL"
echo "=========================================="

echo "Docker Image: $IMAGE"
echo "Build ID: $BUILD_ID"
echo "Active Port: $NEW_PORT"
echo "Application URL: http://3.239.220.63/"
echo "Health URL: http://3.239.220.63/health"

echo "=========================================="

if [[ "$HAD_ACTIVE" == "true" ]]; then

    echo "Previous container $CURRENT_CONTAINER retained for rollback."

else

    echo "Initial deployment completed."

fi

echo "=========================================="

exit 0
