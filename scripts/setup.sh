#!/bin/bash
# Apex Agents - Interactive Setup
# Creates configuration for multi-agent coordination via Linear

set -e

CONFIG_DIR="$HOME/.config/apex-agents"
CONFIG_FILE="$CONFIG_DIR/config.json"

echo "🦞 Apex Agents Setup"
echo "===================="
echo ""

# Create config directory
mkdir -p "$CONFIG_DIR"

# Check for existing config
if [ -f "$CONFIG_FILE" ]; then
    echo "⚠️  Existing config found at $CONFIG_FILE"
    read -p "Overwrite? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Step 1: Linear API Key
echo ""
echo "Step 1: Linear API Key"
echo "----------------------"
echo "Get your API key from: Linear Settings → API → Personal API keys"
echo ""
read -p "Paste your Linear API key: " LINEAR_API_KEY

if [ -z "$LINEAR_API_KEY" ]; then
    echo "❌ API key required"
    exit 1
fi

# Validate API key by fetching teams
echo ""
echo "Validating API key..."
TEAMS_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d '{"query": "{ teams { nodes { id name } } viewer { id name email } }"}')

# Check for errors
if echo "$TEAMS_RESPONSE" | grep -q '"errors"'; then
    echo "❌ Invalid API key or API error"
    echo "$TEAMS_RESPONSE"
    exit 1
fi

VIEWER_NAME=$(echo "$TEAMS_RESPONSE" | jq -r '.data.viewer.name // "Unknown"')
VIEWER_EMAIL=$(echo "$TEAMS_RESPONSE" | jq -r '.data.viewer.email // "Unknown"')
echo "✅ Connected as: $VIEWER_NAME ($VIEWER_EMAIL)"

# Step 2: Select Team
echo ""
echo "Step 2: Select Team"
echo "-------------------"
echo "Available teams:"
echo "$TEAMS_RESPONSE" | jq -r '.data.teams.nodes[] | "  - \(.name) (ID: \(.id))"'
echo ""

TEAM_COUNT=$(echo "$TEAMS_RESPONSE" | jq '.data.teams.nodes | length')
if [ "$TEAM_COUNT" -eq 1 ]; then
    TEAM_ID=$(echo "$TEAMS_RESPONSE" | jq -r '.data.teams.nodes[0].id')
    TEAM_NAME=$(echo "$TEAMS_RESPONSE" | jq -r '.data.teams.nodes[0].name')
    echo "Auto-selected: $TEAM_NAME"
else
    read -p "Enter Team ID: " TEAM_ID
    TEAM_NAME=$(echo "$TEAMS_RESPONSE" | jq -r --arg id "$TEAM_ID" '.data.teams.nodes[] | select(.id == $id) | .name')
fi

if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" == "null" ]; then
    echo "❌ Invalid team ID"
    exit 1
fi

echo "✅ Selected team: $TEAM_NAME"

# Step 3: Agent Identity
echo ""
echo "Step 3: Agent Identity"
echo "----------------------"
read -p "What should this agent be called? (e.g., Saidi, Atlas, Nova): " AGENT_NAME

if [ -z "$AGENT_NAME" ]; then
    AGENT_NAME="Agent"
fi

echo ""
echo "What role does this agent have?"
echo "  1. queen  - Coordinator (receives goals, assigns to workers)"
echo "  2. worker - Executor (receives tasks, reports to queen)"
read -p "Role (queen/worker) [worker]: " AGENT_ROLE
AGENT_ROLE=${AGENT_ROLE:-worker}

if [ "$AGENT_ROLE" != "queen" ] && [ "$AGENT_ROLE" != "worker" ]; then
    AGENT_ROLE="worker"
fi

echo ""
echo "What domains does this agent handle? (comma-separated)"
echo "Examples: business, scheduling, emails, technical, code, deployment"
read -p "Domains: " DOMAINS_INPUT

# Convert to JSON array
DOMAINS_JSON=$(echo "$DOMAINS_INPUT" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)

# Hive configuration based on role
HIVE_JSON="{}"
if [ "$AGENT_ROLE" == "queen" ]; then
    echo ""
    echo "Step 3b: Configure Workers"
    echo "--------------------------"
    WORKERS_ARRAY="[]"
    while true; do
        read -p "Add a worker? (y/N): " add_worker
        if [ "$add_worker" != "y" ] && [ "$add_worker" != "Y" ]; then
            break
        fi
        read -p "  Worker name: " W_NAME
        read -p "  Worker domains (comma-separated): " W_DOMAINS
        read -p "  Worker endpoint (local or URL, default: local): " W_ENDPOINT
        W_ENDPOINT=${W_ENDPOINT:-local}
        
        W_DOMAINS_JSON=$(echo "$W_DOMAINS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
        WORKERS_ARRAY=$(echo "$WORKERS_ARRAY" | jq --arg name "$W_NAME" --argjson domains "$W_DOMAINS_JSON" --arg endpoint "$W_ENDPOINT" \
            '. + [{"name": $name, "domains": $domains, "endpoint": $endpoint}]')
    done
    HIVE_JSON=$(jq -n --argjson workers "$WORKERS_ARRAY" '{"workers": $workers}')
else
    echo ""
    echo "Step 3b: Configure Queen"
    echo "------------------------"
    read -p "Queen agent name (or press Enter if not set up yet): " QUEEN_NAME
    if [ -n "$QUEEN_NAME" ]; then
        HIVE_JSON=$(jq -n --arg queen "$QUEEN_NAME" '{"queenName": $queen}')
    fi
fi

# Step 4: Partner Agents (Optional)
echo ""
echo "Step 4: Partner Agents (Optional)"
echo "----------------------------------"
read -p "Add a partner agent? (y/N): " add_partner

PARTNERS_JSON="[]"
if [ "$add_partner" == "y" ] || [ "$add_partner" == "Y" ]; then
    read -p "Partner agent name: " PARTNER_NAME
    read -p "Partner's A2A endpoint (or press Enter to skip): " PARTNER_ENDPOINT
    
    if [ -n "$PARTNER_ENDPOINT" ]; then
        PARTNERS_JSON=$(jq -n --arg name "$PARTNER_NAME" --arg endpoint "$PARTNER_ENDPOINT" \
            '[{"name": $name, "a2aEndpoint": $endpoint}]')
    else
        PARTNERS_JSON=$(jq -n --arg name "$PARTNER_NAME" '[{"name": $name}]')
    fi
fi

# Step 5: Settings
echo ""
echo "Step 5: Settings"
echo "----------------"
read -p "Require approval before executing tasks? (Y/n): " approval
APPROVAL_REQUIRED=true
if [ "$approval" == "n" ] || [ "$approval" == "N" ]; then
    APPROVAL_REQUIRED=false
fi

read -p "Check interval in minutes (default: 30): " interval
CHECK_INTERVAL=${interval:-30}

read -p "Auto-assign unowned tasks in your domain? (y/N): " auto_assign
AUTO_ASSIGN=false
if [ "$auto_assign" == "y" ] || [ "$auto_assign" == "Y" ]; then
    AUTO_ASSIGN=true
fi

# Generate config
echo ""
echo "Generating configuration..."

# Build final config with jq for proper JSON
jq -n \
  --arg apiKey "$LINEAR_API_KEY" \
  --arg teamId "$TEAM_ID" \
  --arg teamName "$TEAM_NAME" \
  --arg agentName "$AGENT_NAME" \
  --arg role "$AGENT_ROLE" \
  --argjson domains "$DOMAINS_JSON" \
  --argjson partners "$PARTNERS_JSON" \
  --argjson hive "$HIVE_JSON" \
  --argjson approval "$APPROVAL_REQUIRED" \
  --argjson interval "$CHECK_INTERVAL" \
  --argjson autoAssign "$AUTO_ASSIGN" \
  '{
    linear: {
      apiKey: $apiKey,
      teamId: $teamId,
      teamName: $teamName
    },
    agent: {
      name: $agentName,
      role: $role,
      domains: $domains
    },
    hive: $hive,
    partners: $partners,
    settings: {
      approvalRequired: $approval,
      checkIntervalMinutes: $interval,
      autoAssignUnowned: $autoAssign
    }
  }' > "$CONFIG_FILE"

# Secure the config file (contains API key)
chmod 600 "$CONFIG_FILE"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo ""
cat "$CONFIG_FILE" | jq '.'
echo ""
echo "Next steps:"
echo "1. Add heartbeat integration (see SKILL.md)"
echo "2. Assign tasks to '$AGENT_NAME' in Linear"
echo "3. Your agent will pick them up automatically!"
echo ""
echo "🦞 Happy coordinating!"
