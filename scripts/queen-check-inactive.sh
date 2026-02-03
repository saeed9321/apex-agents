#!/bin/bash
# Apex Agents - Queen: detect inactive workers and print a report
# Reads APEX_PRESENCE markers from the Hive Coordination channel and reports workers
# whose lastSeenAt is older than THRESHOLD_HOURS (default 5).
#
# Output:
# - If none inactive: prints "OK: no inactive workers" and exits 0
# - If any inactive: prints lines "INACTIVE: <name> last seen <hours>h ago" and exits 2

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"
STATE_FILE="$HOME/.config/apex-agents/state.json"

THRESHOLD_HOURS="${THRESHOLD_HOURS:-5}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found. Run setup.sh first."; exit 1
fi

ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")
if [ "$ROLE" != "queen" ]; then
  echo "❌ This command is for Queen only. Current role: $ROLE"; exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
HIVE_ID=$(jq -r '.hive.hiveId // empty' "$CONFIG_FILE")

if [ -z "$HIVE_ID" ]; then
  echo "❌ Missing hive.hiveId in config."; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COORD_ISSUE_ID=$(bash "$SCRIPT_DIR/hive-channel.sh" get)

if [ -z "$COORD_ISSUE_ID" ]; then
  echo "❌ Could not resolve hive coordination issue id."; exit 1
fi

READ_QUERY='
query($issueId: String!) {
  issue(id: $issueId) {
    comments(first: 250) {
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

# Extract presence JSON payloads
BODIES=$(echo "$RESP" | jq -r '.data.issue.comments.nodes[].body // ""')
PRESENCE_PAYLOADS=$(echo "$BODIES" | awk '/^APEX_PRESENCE[[:space:]]*\{/{sub(/^APEX_PRESENCE[[:space:]]*/, ""); print}')

if [ -z "$PRESENCE_PAYLOADS" ]; then
  echo "OK: no presence markers found"
  exit 0
fi

NOW_EPOCH=$(date -u +%s)

# Use python to: parse JSON lines, filter by hiveId/role, keep latest lastSeenAt per name
REPORT=$(HIVE_ID="$HIVE_ID" THRESHOLD_HOURS="$THRESHOLD_HOURS" NOW_EPOCH="$NOW_EPOCH" python3 - <<'PY'
import json, os, sys
from datetime import datetime

hive_id = os.environ.get('HIVE_ID')
threshold_hours = float(os.environ.get('THRESHOLD_HOURS','5'))
now_epoch = int(os.environ.get('NOW_EPOCH'))

latest = {}  # name -> (last_seen_epoch, payload)

def parse_iso(s):
    # Linear uses ISO8601 with Z
    try:
        dt = datetime.fromisoformat(s.replace('Z','+00:00'))
        return int(dt.timestamp())
    except Exception:
        return None

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        p = json.loads(line)
    except Exception:
        continue
    if p.get('hiveId') != hive_id:
        continue
    if str(p.get('role','')) != 'worker':
        continue
    name = p.get('name')
    last = p.get('lastSeenAt')
    if not name or not last:
        continue
    ts = parse_iso(last)
    if ts is None:
        continue
    cur = latest.get(name)
    if cur is None or ts > cur[0]:
        latest[name] = (ts, p)

inactive = []
for name, (ts, p) in latest.items():
    age_s = max(0, now_epoch - ts)
    age_h = age_s / 3600.0
    if age_h >= threshold_hours:
        inactive.append((age_h, name, p))

inactive.sort(reverse=True)

if not inactive:
    print('OK: no inactive workers')
    sys.exit(0)

for age_h, name, p in inactive:
    print(f"INACTIVE: {name} last seen {age_h:.1f}h ago")

sys.exit(2)
PY
)
STATUS=$?

echo "$REPORT"
exit $STATUS
