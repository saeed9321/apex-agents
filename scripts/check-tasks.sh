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

# Post worker presence for inactivity monitoring (best-effort)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$ROLE" = "worker" ] && [ -x "$SCRIPT_DIR/worker-presence.sh" ]; then
  "$SCRIPT_DIR/worker-presence.sh" >/dev/null 2>&1 || true
fi

# Initialize state file if needed
if [ ! -f "$STATE_FILE" ]; then
    echo '{"lastCheck": 0, "processedTasks": []}' > "$STATE_FILE"
fi

# GraphQL query to get assigned issues
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

echo "📋 Found $ISSUE_COUNT active issues in team"

# Filter for tasks assigned to this agent (by name in comments/labels or assignee)
# For now, we look for tasks with agent name mentioned or labeled
MY_TASKS=$(echo "$ISSUES" | jq --arg agent "$AGENT_NAME" '
  [.[] | select(
    (.assignee.name // "" | ascii_downcase | contains($agent | ascii_downcase)) or
    (.labels.nodes[]?.name // "" | ascii_downcase | contains($agent | ascii_downcase)) or
    (.title | ascii_downcase | contains("@" + ($agent | ascii_downcase))) or
    (.description // "" | ascii_downcase | contains("@" + ($agent | ascii_downcase)))
  )]
')

MY_TASK_COUNT=$(echo "$MY_TASKS" | jq 'length')

if [ "$MY_TASK_COUNT" -eq 0 ]; then
    echo "✅ No tasks assigned to $AGENT_NAME"
    
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
