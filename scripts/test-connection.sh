#!/bin/bash
# Apex Agents - Test Linear connection

CONFIG_FILE="$HOME/.config/apex-agents/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found at $CONFIG_FILE"
    echo "Run setup.sh first."
    exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
TEAM_NAME=$(jq -r '.linear.teamName' "$CONFIG_FILE")
AGENT_NAME=$(jq -r '.agent.name' "$CONFIG_FILE")

echo "🔍 Testing Linear connection..."
echo ""

# Test API connection
RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d '{"query": "{ viewer { id name email } }"}')

if echo "$RESPONSE" | grep -q '"errors"'; then
    echo "❌ Connection failed!"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

VIEWER_NAME=$(echo "$RESPONSE" | jq -r '.data.viewer.name')
VIEWER_EMAIL=$(echo "$RESPONSE" | jq -r '.data.viewer.email')

echo "✅ Connection successful!"
echo ""
echo "Account: $VIEWER_NAME ($VIEWER_EMAIL)"
echo "Team: $TEAM_NAME ($TEAM_ID)"
echo "Agent: $AGENT_NAME"
echo ""

# Get team stats
STATS_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $API_KEY" \
    -d "$(jq -n --arg teamId "$TEAM_ID" '{
        query: "query($teamId: String!) { team(id: $teamId) { issueCount members { nodes { name } } } }",
        variables: {teamId: $teamId}
    }')")

ISSUE_COUNT=$(echo "$STATS_RESPONSE" | jq -r '.data.team.issueCount // 0')
MEMBER_COUNT=$(echo "$STATS_RESPONSE" | jq '.data.team.members.nodes | length')

echo "Team Stats:"
echo "  - Issues: $ISSUE_COUNT"
echo "  - Members: $MEMBER_COUNT"
echo ""
echo "🦞 Ready to coordinate!"
