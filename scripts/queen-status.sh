#!/bin/bash
# Apex Agents - Queen: Get status of all workers and tasks
# Usage: queen-status.sh

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

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
WORKERS=$(jq -c '.hive.workers // []' "$CONFIG_FILE")

echo "👑 Queen Status Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get all active issues
QUERY='
query($teamId: String!) {
  team(id: $teamId) {
    issues(
      filter: { state: { type: { nin: ["completed", "canceled"] } } }
      first: 100
    ) {
      nodes {
        id
        identifier
        title
        description
        state { name type }
        createdAt
        updatedAt
      }
    }
  }
}
'

RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d "$(jq -n --arg query "$QUERY" --arg teamId "$TEAM_ID" \
        '{query: $query, variables: {teamId: $teamId}}')")

ISSUES=$(echo "$RESPONSE" | jq '.data.team.issues.nodes')

# Group by worker
echo "## Workers"
echo ""

echo "$WORKERS" | jq -r '.[] | .name' | while read -r WORKER; do
    WORKER_LOWER=$(echo "$WORKER" | tr '[:upper:]' '[:lower:]')
    WORKER_TASKS=$(echo "$ISSUES" | jq --arg w "$WORKER_LOWER" '
        [.[] | select(.description // "" | ascii_downcase | contains("@" + $w))]
    ')
    TASK_COUNT=$(echo "$WORKER_TASKS" | jq 'length')
    
    DOMAINS=$(echo "$WORKERS" | jq -r --arg w "$WORKER" '.[] | select(.name == $w) | .domains | join(", ")')
    
    echo "### 🐝 $WORKER"
    echo "   Domains: $DOMAINS"
    echo "   Active tasks: $TASK_COUNT"
    
    if [ "$TASK_COUNT" -gt 0 ]; then
        echo "$WORKER_TASKS" | jq -r '.[] | "   - [\(.state.name)] \(.identifier): \(.title)"'
    fi
    echo ""
done

# Summary stats
TOTAL_TASKS=$(echo "$ISSUES" | jq 'length')
IN_PROGRESS=$(echo "$ISSUES" | jq '[.[] | select(.state.type == "started")] | length')
BACKLOG=$(echo "$ISSUES" | jq '[.[] | select(.state.type == "backlog" or .state.type == "unstarted")] | length')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "## Summary"
echo "   Total active: $TOTAL_TASKS"
echo "   In progress: $IN_PROGRESS"
echo "   Backlog: $BACKLOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
