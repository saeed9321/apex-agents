#!/bin/bash
# Apex Agents - Queen: Assign task to worker
# Usage: queen-assign.sh "Task title" "worker-name" "description"

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")
if [ "$ROLE" != "queen" ]; then
    echo "❌ This command is for Queen only. Current role: $ROLE"
    exit 1
fi

TITLE="$1"
WORKER="$2"
DESCRIPTION="$3"

if [ -z "$TITLE" ] || [ -z "$WORKER" ]; then
    echo "Usage: queen-assign.sh \"Task title\" \"worker-name\" [\"description\"]"
    exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")

# Verify worker exists
WORKER_EXISTS=$(jq -r --arg w "$WORKER" '.hive.workers[] | select(.name == $w) | .name' "$CONFIG_FILE")
if [ -z "$WORKER_EXISTS" ]; then
    echo "❌ Worker '$WORKER' not found. Available workers:"
    jq -r '.hive.workers[].name' "$CONFIG_FILE"
    exit 1
fi

echo "👑 Queen: Creating task for $WORKER..."

# Create issue in Linear with worker label
MUTATION='
mutation CreateIssue($teamId: String!, $title: String!, $description: String) {
  issueCreate(input: {
    teamId: $teamId
    title: $title
    description: $description
  }) {
    success
    issue {
      id
      identifier
      url
    }
  }
}
'

# Build description with worker assignment
FULL_DESC="**Assigned to:** @$WORKER

$DESCRIPTION

---
*Created by Queen via apex-agents*"

RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d "$(jq -n \
        --arg query "$MUTATION" \
        --arg teamId "$TEAM_ID" \
        --arg title "$TITLE" \
        --arg desc "$FULL_DESC" \
        '{query: $query, variables: {teamId: $teamId, title: $title, description: $desc}}')")

if echo "$RESPONSE" | jq -e '.data.issueCreate.success' > /dev/null 2>&1; then
    ISSUE_ID=$(echo "$RESPONSE" | jq -r '.data.issueCreate.issue.identifier')
    ISSUE_URL=$(echo "$RESPONSE" | jq -r '.data.issueCreate.issue.url')
    echo ""
    echo "✅ Task created: $ISSUE_ID"
    echo "   Title: $TITLE"
    echo "   Worker: $WORKER"
    echo "   URL: $ISSUE_URL"
    echo ""
    
    # Notify worker if they have an endpoint
    WORKER_ENDPOINT=$(jq -r --arg w "$WORKER" '.hive.workers[] | select(.name == $w) | .endpoint // "none"' "$CONFIG_FILE")
    if [ "$WORKER_ENDPOINT" != "none" ] && [ "$WORKER_ENDPOINT" != "local" ] && [ -n "$WORKER_ENDPOINT" ]; then
        echo "📤 Notifying $WORKER at $WORKER_ENDPOINT..."
        # A2A notification would go here
    fi
else
    echo "❌ Failed to create task"
    echo "$RESPONSE" | jq '.'
    exit 1
fi
