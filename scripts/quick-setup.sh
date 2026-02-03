#!/bin/bash
# Apex Agents - Quick Setup (All-in-One)
# One script to rule them all

set -e

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       🐝 APEX AGENTS SETUP 🐝        ║"
echo "  ║    Multi-Agent Coordination Hive     ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

CONFIG_DIR="$HOME/.config/apex-agents"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

# Step 1: Role Selection
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 1: What's your role?               │"
echo "├─────────────────────────────────────────┤"
echo "│  [Q] Queen  - You coordinate the hive   │"
echo "│  [W] Worker - You execute tasks         │"
echo "└─────────────────────────────────────────┘"
read -p "Enter Q or W: " ROLE_CHOICE

case "$ROLE_CHOICE" in
    [Qq]) ROLE="queen" ;;
    [Ww]) ROLE="worker" ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

echo "✓ Role: $ROLE"
echo ""

# Step 2: Agent Name
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 2: Name your agent                 │"
echo "└─────────────────────────────────────────┘"
read -p "Agent name: " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-"Agent-$(openssl rand -hex 4)"}
echo "✓ Name: $AGENT_NAME"
echo ""

# Step 3: Linear Connection
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 3: Connect to Linear               │"
echo "├─────────────────────────────────────────┤"
echo "│ Get API key: Linear → Settings → API   │"
echo "└─────────────────────────────────────────┘"
read -p "Linear API Key: " LINEAR_KEY

# Validate and get teams
echo "Connecting..."
TEAMS=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_KEY" \
    -d '{"query": "{ teams { nodes { id name } } viewer { name } }"}')

if echo "$TEAMS" | grep -q '"errors"'; then
    echo "❌ Invalid API key"
    exit 1
fi

VIEWER=$(echo "$TEAMS" | jq -r '.data.viewer.name')
echo "✓ Connected as: $VIEWER"

# Select team
TEAM_COUNT=$(echo "$TEAMS" | jq '.data.teams.nodes | length')
if [ "$TEAM_COUNT" -eq 1 ]; then
    TEAM_ID=$(echo "$TEAMS" | jq -r '.data.teams.nodes[0].id')
    TEAM_NAME=$(echo "$TEAMS" | jq -r '.data.teams.nodes[0].name')
    echo "✓ Team: $TEAM_NAME"
else
    echo ""
    echo "Select team:"
    echo "$TEAMS" | jq -r '.data.teams.nodes | to_entries | .[] | "  [\(.key + 1)] \(.value.name)"'
    read -p "Team number: " TEAM_NUM
    TEAM_ID=$(echo "$TEAMS" | jq -r ".data.teams.nodes[$((TEAM_NUM - 1))].id")
    TEAM_NAME=$(echo "$TEAMS" | jq -r ".data.teams.nodes[$((TEAM_NUM - 1))].name")
fi
echo ""

# Step 4: Hive Configuration
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 4: Hive Configuration              │"
echo "└─────────────────────────────────────────┘"

if [ "$ROLE" == "queen" ]; then
    # Queen generates hive ID
    HIVE_ID="hive-$(openssl rand -hex 6)"
    echo "✓ Generated Hive ID: $HIVE_ID"
    echo ""
    echo "📋 Share this with your workers!"
    QUEEN_NAME="$AGENT_NAME"
    
    # Ask for initial workers
    WORKERS="[]"
    echo ""
    echo "Add workers (you can add more later):"
    while true; do
        read -p "Add worker? (y/N): " ADD_WORKER
        [ "$ADD_WORKER" != "y" ] && [ "$ADD_WORKER" != "Y" ] && break
        
        read -p "  Worker name: " W_NAME
        read -p "  Domains (comma-separated): " W_DOMAINS
        
        W_DOMAINS_JSON=$(echo "$W_DOMAINS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
        WORKERS=$(echo "$WORKERS" | jq --arg name "$W_NAME" --argjson domains "$W_DOMAINS_JSON" \
            '. + [{"name": $name, "domains": $domains, "endpoint": "linear"}]')
    done
else
    # Worker joins existing hive
    read -p "Enter Hive ID (from Queen): " HIVE_ID
    read -p "Queen's name: " QUEEN_NAME
fi

# Step 5: Domains
echo ""
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 5: Your Domains                    │"
echo "├─────────────────────────────────────────┤"
echo "│ What areas do you handle?               │"
echo "│ Examples: business, technical, design   │"
echo "└─────────────────────────────────────────┘"
read -p "Domains (comma-separated): " DOMAINS_INPUT
DOMAINS_JSON=$(echo "$DOMAINS_INPUT" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)

# Step 6: Approval Setting
echo ""
echo "┌─────────────────────────────────────────┐"
echo "│ STEP 6: Approval Mode                   │"
echo "├─────────────────────────────────────────┤"
echo "│ [A] Ask before acting (safer)           │"
echo "│ [F] Fully autonomous (faster)           │"
echo "└─────────────────────────────────────────┘"
read -p "Enter A or F [A]: " APPROVAL_CHOICE
APPROVAL_CHOICE=${APPROVAL_CHOICE:-A}

case "$APPROVAL_CHOICE" in
    [Aa]) APPROVAL=true ;;
    [Ff]) APPROVAL=false ;;
    *) APPROVAL=true ;;
esac

# Generate config
if [ "$ROLE" == "queen" ]; then
    HIVE_JSON=$(jq -n \
        --arg hiveId "$HIVE_ID" \
        --argjson workers "$WORKERS" \
        '{hiveId: $hiveId, workers: $workers}')
else
    HIVE_JSON=$(jq -n \
        --arg hiveId "$HIVE_ID" \
        --arg queenName "$QUEEN_NAME" \
        '{hiveId: $hiveId, queenName: $queenName}')
fi

jq -n \
    --arg apiKey "$LINEAR_KEY" \
    --arg teamId "$TEAM_ID" \
    --arg teamName "$TEAM_NAME" \
    --arg name "$AGENT_NAME" \
    --arg role "$ROLE" \
    --argjson domains "$DOMAINS_JSON" \
    --argjson hive "$HIVE_JSON" \
    --argjson approval "$APPROVAL" \
    '{
        linear: {apiKey: $apiKey, teamId: $teamId, teamName: $teamName},
        agent: {name: $name, role: $role, domains: $domains},
        hive: $hive,
        settings: {approvalRequired: $approval, checkIntervalMinutes: 30, logToLinear: true}
    }' > "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"

# Create coordination channel
echo ""
echo "Setting up coordination channel..."
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/hive-channel.sh" ]; then
    bash "$SCRIPT_DIR/hive-channel.sh" get > /dev/null 2>&1
    bash "$SCRIPT_DIR/hive-channel.sh" post "🐝 **$AGENT_NAME** joined the hive as $ROLE"
fi

# Done!
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║              ✅ SETUP COMPLETE!                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Agent:    $AGENT_NAME"
echo "  Role:     $ROLE"
echo "  Hive ID:  $HIVE_ID"
echo "  Team:     $TEAM_NAME"
echo "  Approval: $([ "$APPROVAL" == "true" ] && echo "Ask first" || echo "Autonomous")"
echo ""

if [ "$ROLE" == "queen" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "👑 QUEEN COMMANDS:"
    echo ""
    echo "  Assign task:    bash scripts/queen-assign.sh \"Task\" \"Worker\" \"Description\""
    echo "  Check status:   bash scripts/queen-status.sh"
    echo "  Post to hive:   bash scripts/hive-channel.sh post \"Message\""
    echo "  Read hive chat: bash scripts/hive-channel.sh read"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 SHARE WITH WORKERS:"
    echo ""
    echo "  Hive ID: $HIVE_ID"
    echo "  Linear Workspace: $TEAM_NAME"
    echo "  (They need Linear access to this workspace)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐝 WORKER COMMANDS:"
    echo ""
    echo "  Check tasks:    bash scripts/check-tasks.sh"
    echo "  Update task:    bash scripts/update-task.sh <id> status \"In Progress\""
    echo "  Post to hive:   bash scripts/hive-channel.sh post \"Message\""
    echo "  Read hive chat: bash scripts/hive-channel.sh read"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "🐝 Hive coordination channel created in Linear!"
echo "   All agent messages are logged there for humans to monitor."
echo ""
