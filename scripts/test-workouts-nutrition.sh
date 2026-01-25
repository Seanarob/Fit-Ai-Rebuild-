#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
USER_ID="${USER_ID:-}"
RUN_AI="${RUN_AI:-0}"

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

echo "Creating a manual workout template..."
curl -s -X POST "$BASE_URL/workouts/templates" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\",\"title\":\"Test Template\",\"mode\":\"manual\",\"exercises\":[{\"name\":\"Bench Press\",\"muscle_groups\":[\"chest\"],\"equipment\":[\"barbell\"],\"sets\":3,\"reps\":8,\"rest_seconds\":120},{\"name\":\"Pull Up\",\"muscle_groups\":[\"back\"],\"equipment\":[\"bodyweight\"],\"sets\":3,\"reps\":6,\"rest_seconds\":120}]}" | pretty

echo "Searching exercises..."
curl -s "$BASE_URL/exercises/search?query=Bench" | pretty

echo "Searching food items..."
curl -s "$BASE_URL/nutrition/search?query=chicken&user_id=$USER_ID" | pretty

if [[ "$RUN_AI" == "1" ]]; then
  echo "Running AI workout generation (requires OPENAI_API_KEY on backend)..."
  curl -s -X POST "$BASE_URL/workouts/generate" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"$USER_ID\",\"muscle_groups\":[\"full body\"],\"workout_type\":\"strength\",\"equipment\":[\"dumbbells\"]}" | pretty

  echo "Running AI meal photo parse (requires OPENAI_API_KEY on backend)..."
  curl -s -X POST "$BASE_URL/nutrition/log?user_id=$USER_ID&meal_type=lunch" | pretty
else
  echo "Skipping AI endpoints. Set RUN_AI=1 to test workout generation and meal photo parse."
fi
