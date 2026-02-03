#!/bin/bash
# Apex Agents - Easy A2A Setup
# Generates shared config for all agents to connect

set -e

CONFIG_DIR="$HOME/.config/apex-agents"
CONFIG_FILE="$CONFIG_DIR/config.json"
A2A_FILE="$CONFIG_DIR/a2a-shared.json"

echo "🔗 Apex Agents - A2A Easy Setup"
echo "================================"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Run setup.sh first to configure Linear connection"
    exit 1
fi

AGENT_NAME=$(jq -r '.agent.name' "$CONFIG_FILE")
ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")

echo "Agent: $AGENT_NAME (Role: $ROLE)"
echo ""

# Generate or load hive ID
HIVE_ID=$(jq -r '.hive.hiveId // empty' "$CONFIG_FILE")
if [ -z "$HIVE_ID" ]; then
    if [ "$ROLE" == "queen" ]; then
        # Queen generates new hive ID
        HIVE_ID="hive-$(openssl rand -hex 8)"
        echo "👑 Generated new Hive ID: $HIVE_ID"
        
        # Update config with hive ID
        jq --arg hiveId "$HIVE_ID" '.hive.hiveId = $hiveId' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        echo "Enter Hive ID (get from Queen):"
        read -p "Hive ID: " HIVE_ID
        
        jq --arg hiveId "$HIVE_ID" '.hive.hiveId = $hiveId' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
fi

# Generate shared config for other agents
LINEAR_TEAM=$(jq -r '.linear.teamId' "$CONFIG_FILE")
LINEAR_TEAM_NAME=$(jq -r '.linear.teamName' "$CONFIG_FILE")

cat > "$A2A_FILE" << EOF
{
  "hiveId": "$HIVE_ID",
  "linear": {
    "teamId": "$LINEAR_TEAM",
    "teamName": "$LINEAR_TEAM_NAME"
  },
  "queen": {
    "name": "$([ "$ROLE" == "queen" ] && echo "$AGENT_NAME" || jq -r '.hive.queenName // "Unknown"' "$CONFIG_FILE")"
  },
  "coordinationChannel": "linear-comments",
  "created": "$(date -Iseconds)",
  "createdBy": "$AGENT_NAME"
}
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ A2A Configuration Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Share this with your team:"
echo ""
cat "$A2A_FILE" | jq '.'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ROLE" == "queen" ]; then
    echo "👑 You're the Queen. Share this info with workers:"
    echo ""
    echo "   Hive ID: $HIVE_ID"
    echo "   Linear Team: $LINEAR_TEAM_NAME"
    echo ""
    echo "Workers run:"
    echo "   bash scripts/setup.sh"
    echo "   (Choose 'worker', enter Hive ID: $HIVE_ID)"
else
    echo "🐝 You're a Worker. Your Queen should see you now."
fi
echo ""
