#!/bin/bash
# Apex Agents - Create/Get Hive Coordination Channel
# A Linear issue where all agent coordination is logged

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"
STATE_FILE="$HOME/.config/apex-agents/state.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
HIVE_ID=$(jq -r '.hive.hiveId // "default"' "$CONFIG_FILE")
AGENT_NAME=$(jq -r '.agent.name' "$CONFIG_FILE")

ACTION="${1:-get}"
MESSAGE="$2"

# Initialize state if needed
if [ ! -f "$STATE_FILE" ]; then
    echo '{"coordinationIssueId": null}' > "$STATE_FILE"
fi

COORD_ISSUE_ID=$(jq -r '.coordinationIssueId // empty' "$STATE_FILE")

# Find or create coordination issue
find_or_create_channel() {
    # Search for existing coordination issue
    SEARCH_QUERY='
    query($teamId: String!) {
      team(id: $teamId) {
        issues(filter: { title: { contains: "[Hive Coordination]" } }, first: 1) {
          nodes {
            id
            identifier
          }
        }
      }
    }
    '
    
    SEARCH_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Content-Type: application/json" \
        -H "Authorization: $API_KEY" \
        -d "$(jq -n --arg query "$SEARCH_QUERY" --arg teamId "$TEAM_ID" \
            '{query: $query, variables: {teamId: $teamId}}')")
    
    EXISTING_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.data.team.issues.nodes[0].id // empty')
    
    if [ -n "$EXISTING_ID" ]; then
        echo "$EXISTING_ID"
        return
    fi
    
    # Create new coordination issue
    CREATE_MUTATION='
    mutation CreateCoordIssue($teamId: String!, $title: String!, $description: String!) {
      issueCreate(input: {
        teamId: $teamId
        title: $title
        description: $description
      }) {
        success
        issue {
          id
          identifier
        }
      }
    }
    '
    
    TITLE="[Hive Coordination] 🐝 Agent Communication Channel"
    DESC="**This is the coordination channel for the Apex Agents hive.**

All agent-to-agent communication is logged here as comments.

- **Hive ID:** $HIVE_ID
- **Created:** $(date)

---

Humans can monitor agent discussions by watching this issue.
Agents: Post coordination messages as comments below."
    
    CREATE_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Content-Type: application/json" \
        -H "Authorization: $API_KEY" \
        -d "$(jq -n \
            --arg query "$CREATE_MUTATION" \
            --arg teamId "$TEAM_ID" \
            --arg title "$TITLE" \
            --arg desc "$DESC" \
            '{query: $query, variables: {teamId: $teamId, title: $title, description: $desc}}')")
    
    NEW_ID=$(echo "$CREATE_RESPONSE" | jq -r '.data.issueCreate.issue.id // empty')
    echo "$NEW_ID"
}

# Get or create the channel
if [ -z "$COORD_ISSUE_ID" ]; then
    echo "🔍 Finding or creating coordination channel..." >&2
    COORD_ISSUE_ID=$(find_or_create_channel)
    
    if [ -n "$COORD_ISSUE_ID" ]; then
        jq --arg id "$COORD_ISSUE_ID" '.coordinationIssueId = $id' "$STATE_FILE" > "$STATE_FILE.tmp"
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
fi

case "$ACTION" in
    get)
        echo "$COORD_ISSUE_ID"
        ;;
    
    post|say)
        if [ -z "$MESSAGE" ]; then
            echo "Usage: hive-channel.sh post \"Your message\""
            exit 1
        fi
        
        # If this is a structured machine-readable marker (e.g. APEX_JOIN/APEX_PRESENCE),
        # post it raw so it can be parsed reliably from the beginning of the comment body.
        if echo "$MESSAGE" | grep -q '^APEX_'; then
            FORMATTED="$MESSAGE"
        else
            # Human-readable message
            FORMATTED="**🐝 $AGENT_NAME** _($(date +%H:%M))_

$MESSAGE"
        fi
        
        COMMENT_MUTATION='
        mutation AddComment($issueId: String!, $body: String!) {
          commentCreate(input: { issueId: $issueId, body: $body }) {
            success
          }
        }
        '
        
        RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n \
                --arg query "$COMMENT_MUTATION" \
                --arg issueId "$COORD_ISSUE_ID" \
                --arg body "$FORMATTED" \
                '{query: $query, variables: {issueId: $issueId, body: $body}}')")
        
        if echo "$RESPONSE" | jq -e '.data.commentCreate.success' > /dev/null 2>&1; then
            echo "✅ Posted to hive channel"
        else
            echo "❌ Failed to post"
            echo "$RESPONSE" | jq '.'
        fi
        ;;
    
    read)
        # Get recent comments
        READ_QUERY='
        query($issueId: String!) {
          issue(id: $issueId) {
            comments(first: 20) {
              nodes {
                body
                createdAt
                user { name }
              }
            }
          }
        }
        '
        
        RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n \
                --arg query "$READ_QUERY" \
                --arg issueId "$COORD_ISSUE_ID" \
                '{query: $query, variables: {issueId: $issueId}}')")
        
        echo "📜 Recent Hive Messages:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$RESPONSE" | jq -r '.data.issue.comments.nodes[] | "\(.createdAt | split("T")[1] | split(".")[0]) \(.body)\n"'
        ;;
    
    *)
        echo "Usage: hive-channel.sh [get|post|read] [message]"
        ;;
esac
