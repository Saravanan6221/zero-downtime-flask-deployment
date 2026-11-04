#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://127.0.0.1/health}"
ATTEMPTS="${2:-10}"
DELAY="${3:-2}"
for ((i=1; i<=ATTEMPTS; i++)); do
  if curl --fail --silent --show-error --max-time 3 "$URL"; then
    echo
    echo "Health check passed on attempt $i"
    exit 0
  fi
  echo "Health check attempt $i/$ATTEMPTS failed"
  sleep "$DELAY"
done
echo "Health check failed after $ATTEMPTS attempts"
exit 1
