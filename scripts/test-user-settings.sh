#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
USER_ID="${USER_ID:-}"

if [[ -z "$USER_ID" ]]; then
  echo "USER_ID is required. Example: USER_ID=uuid BASE_URL=http://localhost:8000 $0"
  exit 1
fi

pretty() {
  if command -v jq >/dev/null 2>&1; then
    jq
  else
    cat
  fi
}

# Mark tutorial complete
curl -s -X POST "$BASE_URL/users/tutorial/complete" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\",\"completed\":true}" | pretty

# Set check-in day
curl -s -X PUT "$BASE_URL/users/checkin-day" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\",\"check_in_day\":\"monday\"}" | pretty

# Fetch profile
curl -s "$BASE_URL/users/me?user_id=$USER_ID" | pretty
