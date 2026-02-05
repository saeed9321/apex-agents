#!/bin/bash
# Apex Agents - Check for assigned tasks
# Run this from heartbeat or manually

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"
STATE_FILE="$HOME/.config/apex-agents/state.json"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

# Load config
API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
AGENT_NAME=$(jq -r '.agent.name' "$CONFIG_FILE")
APPROVAL_REQUIRED=$(jq -r '.settings.approvalRequired' "$CONFIG_FILE")
ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")

# Autonomous behaviors (non-destructive): commenting + reminding
AUTO_COMMENT_ON_CHECK=$(jq -r '.settings.autoCommentOnCheck // false' "$CONFIG_FILE")
COMMENT_COOLDOWN_MINUTES=$(jq -r '.settings.commentCooldownMinutes // 30' "$CONFIG_FILE")

# Post worker presence for inactivity monitoring (best-effort)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$ROLE" = "worker" ] && [ -x "$SCRIPT_DIR/worker-presence.sh" ]; then
  "$SCRIPT_DIR/worker-presence.sh" >/dev/null 2>&1 || true
fi

# Initialize state file if needed
if [ ! -f "$STATE_FILE" ]; then
    echo '{"lastCheck": 0, "processedTasks": []}' > "$STATE_FILE"
fi

# Resolve the Linear "viewer" (current API key identity). This is the most reliable
# way to detect "my" tasks, since assignee name may differ from config.agent.name.
VIEWER_QUERY='{
  viewer {
    id
    name
    email
  }
}'

VIEWER_RESP=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d "$(jq -n --arg query "$VIEWER_QUERY" '{query: $query}')")

if echo "$VIEWER_RESP" | grep -q '"errors"'; then
  echo "❌ API Error (viewer):"
  echo "$VIEWER_RESP" | jq '.errors'
  exit 1
fi

VIEWER_EMAIL=$(echo "$VIEWER_RESP" | jq -r '.data.viewer.email // empty')
VIEWER_NAME=$(echo "$VIEWER_RESP" | jq -r '.data.viewer.name // empty')

# GraphQL query to get active issues
QUERY='
query GetAssignedIssues($teamId: String!) {
  team(id: $teamId) {
    issues(
      filter: {
        state: { type: { nin: ["completed", "canceled"] } }
      }
      first: 50
      orderBy: updatedAt
    ) {
      nodes {
        id
        identifier
        title
        description
        state {
          name
          type
        }
        assignee {
          name
          email
        }
        labels {
          nodes {
            name
          }
        }
        comments {
          nodes {
            body
            user {
              name
            }
            createdAt
          }
        }
        createdAt
        updatedAt
      }
    }
  }
}
'

# Fetch tasks from Linear
echo "🔍 Checking Linear for tasks..."
RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d "$(jq -n --arg query "$QUERY" --arg teamId "$TEAM_ID" \
        '{query: $query, variables: {teamId: $teamId}}')")

# Check for errors
if echo "$RESPONSE" | grep -q '"errors"'; then
    echo "❌ API Error:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

# Extract issues
ISSUES=$(echo "$RESPONSE" | jq '.data.team.issues.nodes')
ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')

# Helper: unix epoch seconds (portable-ish)
_now_epoch() {
  date +%s
}

# Helper: parse Linear ISO date -> epoch seconds
_iso_to_epoch() {
  # GNU date on Linux supports this
  date -d "$1" +%s 2>/dev/null || echo 0
}

# Helper: generate pending questions based on task title/identifier
_pending_questions() {
  local ident="$1"
  local title="$2"

  case "$ident" in
    *APE-6*)
      cat <<'EOF'
**Pending from Said (to proceed):**
1) API base URL
2) Auth method (API key header / OAuth / JWT) + header name
3) Endpoints needed: upload media, create valuation/analyze, get status/result
4) Example request/response (sample payload)
EOF
      ;;
    *APE-7*)
      cat <<'EOF'
**Pending from Said (to proceed):**
1) WABA_ID + PHONE_NUMBER_ID
2) Permanent access token (or where to retrieve it)
3) Webhook verify token value to use
4) Hosting target for webhook (VPS/Render/AWS) + domain/URL
5) Do we already have Meta app + WhatsApp number approved? (yes/no)
EOF
      ;;
    *APE-8*)
      cat <<'EOF'
**Pending from Said (to proceed):**
1) What exact fields must we collect for valuation (minimum required)?
2) Desired tone: examples (2-3 lines) for Muscat/Omani dialect
3) Output format for valuation response + disclaimer text (if you have one)
4) Where to store session state (Redis/DB/in-memory) + retention
EOF
      ;;
    *)
      echo "**Pending from Said (to proceed):** Confirm priority + desired output for this task." 
      ;;
  esac
}

# Helper: decide whether we should auto-comment (cooldown + marker)
_should_autocomment() {
  local issue_json="$1"
  local cooldown_min="$2"
  local now_epoch="$3"

  local last_marked_at
  last_marked_at=$(echo "$issue_json" | jq -r '.comments.nodes[]? | select(.body|contains("APEX_AUTO_CHECKIN")) | .createdAt' | tail -n 1)

  if [ -z "$last_marked_at" ] || [ "$last_marked_at" = "null" ]; then
    echo "yes"; return
  fi

  local last_epoch
  last_epoch=$(_iso_to_epoch "$last_marked_at")
  if [ "$last_epoch" -le 0 ]; then
    echo "yes"; return
  fi

  local diff=$(( now_epoch - last_epoch ))
  local cooldown_sec=$(( cooldown_min * 60 ))
  if [ "$diff" -ge "$cooldown_sec" ]; then
    echo "yes"
  else
    echo "no"
  fi
}

# Helper: add comment via update-task.sh (best-effort)
_add_comment() {
  local issue_id="$1"
  local body="$2"
  local script_dir="$3"

  if [ -x "$script_dir/update-task.sh" ]; then
    "$script_dir/update-task.sh" "$issue_id" comment "$body" >/dev/null 2>&1 || true
  fi
}


echo "📋 Found $ISSUE_COUNT active issues in team"

# Filter for tasks assigned to this agent.
# Prefer matching by assignee email (viewer), then fall back to name/mentions.
MY_TASKS=$(echo "$ISSUES" | jq --arg agent "$AGENT_NAME" --arg viewerEmail "$VIEWER_EMAIL" '
  [.[] | select(
    ((.assignee.email // "") != "" and (.assignee.email // "") == $viewerEmail) or
    (.assignee.name // "" | ascii_downcase | contains($agent | ascii_downcase)) or
    (.labels.nodes[]?.name // "" | ascii_downcase | contains($agent | ascii_downcase)) or
    (.title | ascii_downcase | contains("@" + ($agent | ascii_downcase))) or
    (.description // "" | ascii_downcase | contains("@" + ($agent | ascii_downcase)))
  )]
')

MY_TASK_COUNT=$(echo "$MY_TASKS" | jq 'length')

if [ "$MY_TASK_COUNT" -eq 0 ]; then
    if [ -n "$VIEWER_EMAIL" ]; then
      echo "✅ No tasks assigned to $AGENT_NAME (viewer: $VIEWER_NAME <$VIEWER_EMAIL>)"
    else
      echo "✅ No tasks assigned to $AGENT_NAME"
    fi
    
    # Update last check time
    jq --arg time "$(date -Iseconds)" '.lastCheck = $time' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    
    exit 0
fi

echo ""
echo "📌 Found $MY_TASK_COUNT task(s) for $AGENT_NAME:"
echo ""

# Output tasks in a format the agent can act on
echo "$MY_TASKS" | jq -r '.[] | "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n🎯 \(.identifier): \(.title)\n   Status: \(.state.name)\n   Created: \(.createdAt | split("T")[0])\n   Description: \(.description // "(none)" | split("\n")[0])"'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Output JSON for agent processing
echo ""
echo "APEX_TASKS_JSON_START"
echo "$MY_TASKS" | jq -c '.'
echo "APEX_TASKS_JSON_END"

# Build a lightweight "pending from human" list for reminders
PENDING=$(echo "$MY_TASKS" | jq '[.[] | {id, identifier, title}]')

# Output pending questions JSON (agent can use to remind human every check)
echo ""
echo "APEX_PENDING_JSON_START"
echo "$PENDING" | jq -c '.'
echo "APEX_PENDING_JSON_END"

# Optional: autonomous non-destructive check-in comments to Linear (no code execution)
if [ "$AUTO_COMMENT_ON_CHECK" = "true" ] && [ "$APPROVAL_REQUIRED" = "true" ]; then
  NOW_EPOCH=$(_now_epoch)
  echo ""
  echo "📝 Auto-comment enabled (cooldown: ${COMMENT_COOLDOWN_MINUTES}m). Posting check-in comments where needed..."

  # Iterate tasks and comment if cooldown passed
  echo "$MY_TASKS" | jq -c '.[]' | while read -r ISSUE; do
    ISSUE_ID=$(echo "$ISSUE" | jq -r '.id')
    IDENT=$(echo "$ISSUE" | jq -r '.identifier')
    TITLE=$(echo "$ISSUE" | jq -r '.title')

    SHOULD=$(_should_autocomment "$ISSUE" "$COMMENT_COOLDOWN_MINUTES" "$NOW_EPOCH")
    if [ "$SHOULD" = "yes" ]; then
      QUESTIONS=$(_pending_questions "$IDENT" "$TITLE")
      BODY=$(cat <<EOF
APEX_AUTO_CHECKIN

Checked tasks on schedule. Approval is required before I do any code / repo work.

Task: **$IDENT — $TITLE**

$QUESTIONS

Reply here with the missing info + "Approved to proceed" when ready.
EOF
)
      _add_comment "$ISSUE_ID" "$BODY" "$SCRIPT_DIR"
    fi
  done
fi

# Update state
jq --arg time "$(date -Iseconds)" '.lastCheck = $time' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

# Instructions based on approval setting
echo ""
if [ "$APPROVAL_REQUIRED" == "true" ]; then
    echo "⚠️  Approval required. Notify human before executing."
else
    echo "🚀 Auto-execution enabled. Processing tasks..."
fi
