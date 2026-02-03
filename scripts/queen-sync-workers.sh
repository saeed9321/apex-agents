#!/bin/bash
# Apex Agents - Queen: Sync workers from Hive Coordination channel
# Parses structured join messages posted by workers and updates queen config.
#
# Join marker format (in Linear comments):
#   APEX_JOIN {"name":"WorkerName","role":"worker","domains":[...],"endpoint":"..."...}
#
# Usage:
#   bash scripts/queen-sync-workers.sh

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"
STATE_FILE="$HOME/.config/apex-agents/state.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found. Run setup.sh first."; exit 1
fi

ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")
if [ "$ROLE" != "queen" ]; then
  echo "❌ This command is for Queen only. Current role: $ROLE"; exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
HIVE_ID=$(jq -r '.hive.hiveId // empty' "$CONFIG_FILE")

if [ -z "$HIVE_ID" ]; then
  echo "❌ Missing hive.hiveId in config."; exit 1
fi

# Ensure state file exists (hive-channel uses it for coordinationIssueId)
mkdir -p "$(dirname "$STATE_FILE")"
if [ ! -f "$STATE_FILE" ]; then
  echo '{"coordinationIssueId": null}' > "$STATE_FILE"
fi

SCRIPT_DIR="$(dirname "$0")"
COORD_ISSUE_ID=$(bash "$SCRIPT_DIR/hive-channel.sh" get)

if [ -z "$COORD_ISSUE_ID" ]; then
  echo "❌ Could not resolve hive coordination issue id."; exit 1
fi

echo "👑 Syncing workers from Hive Coordination channel…"

echo "- Hive ID: $HIVE_ID"

# Fetch recent comments (100) from coordination issue
READ_QUERY='
query($issueId: String!) {
  issue(id: $issueId) {
    comments(first: 100) {
      nodes { body createdAt }
    }
  }
}
'

RESP=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $API_KEY" \
  -d "$(jq -n --arg query "$READ_QUERY" --arg issueId "$COORD_ISSUE_ID" '{query:$query, variables:{issueId:$issueId}}')")

if echo "$RESP" | grep -q '"errors"'; then
  echo "❌ Linear API error:" >&2
  echo "$RESP" | jq '.errors' >&2
  exit 1
fi

BODIES=$(echo "$RESP" | jq -r '.data.issue.comments.nodes[].body // ""')

# Extract JSON payloads from lines starting with APEX_JOIN
# We only accept entries matching this hiveId.
JOIN_PAYLOADS=$(echo "$BODIES" | awk '/^APEX_JOIN[[:space:]]*\{/{sub(/^APEX_JOIN[[:space:]]*/, ""); print}')

if [ -z "$JOIN_PAYLOADS" ]; then
  echo "No APEX_JOIN messages found in last 100 comments."
  exit 0
fi

# Convert payloads into a JSON array, filter by hiveId, role=worker, and normalize.
JOIN_ARRAY=$(printf "%s\n" "$JOIN_PAYLOADS" \
  | jq -s 'map(try fromjson catch empty) | map(select(.hiveId == $hiveId and (.role|tostring) == "worker"))' --arg hiveId "$HIVE_ID")

COUNT=$(echo "$JOIN_ARRAY" | jq 'length')
if [ "$COUNT" -eq 0 ]; then
  echo "No worker joins for hiveId=$HIVE_ID found."
  exit 0
fi

# Map joins to worker objects used in queen config.
NEW_WORKERS=$(echo "$JOIN_ARRAY" | jq 'map({name: .name, domains: (.domains // []), endpoint: (.endpoint // "linear")}) | unique_by(.name)')

# Merge into config
TMP=$(mktemp)
cat "$CONFIG_FILE" | jq --argjson workers "$NEW_WORKERS" '
  .hive.workers = ((.hive.workers // []) + $workers | unique_by(.name))
' > "$TMP"

mv "$TMP" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo "✅ Synced $COUNT join event(s). Current workers:" 
jq -r '.hive.workers[] | "- \(.name) (" + (.domains|join(", ")) + ")"' "$CONFIG_FILE"