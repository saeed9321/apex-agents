#!/bin/bash
# Apex Agents - Queen: Decompose goal into tasks
# Usage: queen-decompose.sh "Goal description"

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

GOAL="$1"
if [ -z "$GOAL" ]; then
    echo "Usage: queen-decompose.sh \"Goal description\""
    echo ""
    echo "Example: queen-decompose.sh \"Launch new product by Friday\""
    exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
WORKERS=$(jq -c '.hive.workers // []' "$CONFIG_FILE")

echo "👑 Queen: Analyzing goal..."
echo ""
echo "Goal: $GOAL"
echo ""
echo "Available workers:"
echo "$WORKERS" | jq -r '.[] | "  🐝 \(.name): \(.domains | join(", "))"'
echo ""

# Output format for agent to fill in
cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DECOMPOSITION TEMPLATE (fill this in):

## Tasks

### Task 1
- Title: [task title]
- Assignee: [worker name]
- Domain: [domain]
- Description: [what needs to be done]
- Dependencies: [none / task IDs]

### Task 2
- Title: [task title]
- Assignee: [worker name]
- Domain: [domain]
- Description: [what needs to be done]
- Dependencies: [task 1 / none]

(add more tasks as needed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After decomposition, create tasks in Linear:
  bash scripts/queen-assign.sh "Task title" "worker-name" "description"

EOF
