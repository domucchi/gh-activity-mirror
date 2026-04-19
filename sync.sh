#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WORK_USER="dominik-applifting"
PERSONAL_USER="domucchi"
MIRROR_REPO="domucchi/activity-mirror"
MIRROR_DIR="${SCRIPT_DIR}/.mirror"
STATE_FILE="${SCRIPT_DIR}/state.json"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "  --dry-run  fetch counts and report what would happen, but don't commit or push"
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: $CONFIG_FILE not found. Edit the placeholder values first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${PERSONAL_EMAIL:?PERSONAL_EMAIL must be set in config.env}"
: "${PERSONAL_NAME:?PERSONAL_NAME must be set in config.env}"

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd is not installed" >&2; exit 1; }
done

# On exit, ensure we're switched back to personal so we don't leave the shell on the work account
trap 'gh auth switch --user "$PERSONAL_USER" >/dev/null 2>&1 || true' EXIT

if [[ -f "$STATE_FILE" ]] && [[ -n "$(jq -r '.last_synced_date // empty' "$STATE_FILE")" ]]; then
  FROM=$(jq -r '.last_synced_date' "$STATE_FILE")
else
  FROM=$(date -u -v-1y +%Y-%m-%d)
fi
TO=$(date -u +%Y-%m-%d)

echo "Sync window: $FROM → $TO"

echo "→ gh auth switch --user $WORK_USER"
gh auth switch --user "$WORK_USER" >/dev/null

COUNTS_JSON=$(gh api graphql \
  -f query='
    query($login:String!,$from:DateTime!,$to:DateTime!){
      user(login:$login){
        contributionsCollection(from:$from,to:$to){
          contributionCalendar{
            totalContributions
            weeks{ contributionDays{ date contributionCount } }
          }
        }
      }
    }' \
  -F login="$WORK_USER" \
  -F from="${FROM}T00:00:00Z" \
  -F to="${TO}T23:59:59Z")

echo "→ gh auth switch --user $PERSONAL_USER"
gh auth switch --user "$PERSONAL_USER" >/dev/null

TOTAL=$(echo "$COUNTS_JSON" | jq -r '.data.user.contributionsCollection.contributionCalendar.totalContributions')
echo "Work account reports $TOTAL contributions in window."

ACTIVE_DAYS=$(echo "$COUNTS_JSON" | jq -r --arg from "$FROM" '
  .data.user.contributionsCollection.contributionCalendar.weeks[].contributionDays[]
  | select(.contributionCount > 0 and .date > $from)
  | "\(.date) \(.contributionCount)"')

if [[ -z "$ACTIVE_DAYS" ]]; then
  echo "No new active days since $FROM. Nothing to do."
  exit 0
fi

DAY_COUNT=$(echo "$ACTIVE_DAYS" | wc -l | tr -d ' ')
COMMIT_COUNT=$(echo "$ACTIVE_DAYS" | awk '{s+=$2} END {print s}')
echo "Will mirror $COMMIT_COUNT commits across $DAY_COUNT days."

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "--- DRY RUN: would create the following ---"
  echo "$ACTIVE_DAYS"
  exit 0
fi

if [[ ! -d "$MIRROR_DIR" ]]; then
  echo "Cloning $MIRROR_REPO into $MIRROR_DIR..."
  gh repo clone "$MIRROR_REPO" "$MIRROR_DIR"
fi

cd "$MIRROR_DIR"
git config user.email "$PERSONAL_EMAIL"
git config user.name "$PERSONAL_NAME"

# If repo is freshly created and empty, seed an initial commit so we have a branch to push
if ! git rev-parse HEAD >/dev/null 2>&1; then
  git checkout -B main
  GIT_AUTHOR_NAME="$PERSONAL_NAME" GIT_AUTHOR_EMAIL="$PERSONAL_EMAIL" \
  GIT_COMMITTER_NAME="$PERSONAL_NAME" GIT_COMMITTER_EMAIL="$PERSONAL_EMAIL" \
    git commit --allow-empty -m "init mirror" -q
  git push -u origin main -q
else
  git pull --rebase --quiet
fi

echo "Generating commits..."
while IFS= read -r line; do
  date=$(awk '{print $1}' <<< "$line")
  count=$(awk '{print $2}' <<< "$line")
  for i in $(seq 1 "$count"); do
    # Spread commits through the day starting at noon, in 1s increments,
    # rolling over into minutes/hours for days with lots of activity.
    off=$((i - 1))
    h=$(( 12 + off / 3600 ))
    m=$(( (off % 3600) / 60 ))
    s=$(( off % 60 ))
    ts=$(printf "%sT%02d:%02d:%02d+0000" "$date" "$h" "$m" "$s")
    GIT_AUTHOR_NAME="$PERSONAL_NAME" \
    GIT_AUTHOR_EMAIL="$PERSONAL_EMAIL" \
    GIT_COMMITTER_NAME="$PERSONAL_NAME" \
    GIT_COMMITTER_EMAIL="$PERSONAL_EMAIL" \
    GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_DATE="$ts" \
      git commit --allow-empty -m "mirror activity" -q
  done
done <<< "$ACTIVE_DAYS"

echo "Pushing to $MIRROR_REPO..."
git push --quiet

cd "$SCRIPT_DIR"

if [[ -f "$STATE_FILE" ]]; then
  jq --arg d "$TO" '.last_synced_date = $d' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
else
  printf '{"last_synced_date":"%s"}\n' "$TO" > "$STATE_FILE"
fi

echo
echo "Done. state.json updated to $TO."
echo "Graph should refresh within ~1–2 min at https://github.com/$PERSONAL_USER"
