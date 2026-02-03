#!/bin/bash
# Apex Agents - Update task status or add comment
# Usage: update-task.sh <issue-id> <action> [args]
# Actions: status, comment, complete

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
ISSUE_ID="$1"
ACTION="$2"
shift 2
ARGS="$*"

if [ -z "$ISSUE_ID" ] || [ -z "$ACTION" ]; then
    echo "Usage: update-task.sh <issue-id> <action> [args]"
    echo ""
    echo "Actions:"
    echo "  status <state-name>  - Update issue state (e.g., 'In Progress', 'Done')"
    echo "  comment <text>       - Add a comment"
    echo "  complete            - Mark as completed"
    exit 1
fi

case "$ACTION" in
    comment)
        if [ -z "$ARGS" ]; then
            echo "❌ Comment text required"
            exit 1
        fi
        
        MUTATION='
        mutation AddComment($issueId: String!, $body: String!) {
          commentCreate(input: { issueId: $issueId, body: $body }) {
            success
            comment {
              id
            }
          }
        }
        '
        
        RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n --arg query "$MUTATION" --arg issueId "$ISSUE_ID" --arg body "$ARGS" \
                '{query: $query, variables: {issueId: $issueId, body: $body}}')")
        
        if echo "$RESPONSE" | jq -e '.data.commentCreate.success' > /dev/null; then
            echo "✅ Comment added"
        else
            echo "❌ Failed to add comment"
            echo "$RESPONSE" | jq '.'
        fi
        ;;
        
    status)
        if [ -z "$ARGS" ]; then
            echo "❌ Status name required"
            exit 1
        fi
        
        # First, get the state ID
        TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
        STATES_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n --arg teamId "$TEAM_ID" '{
                query: "query($teamId: String!) { team(id: $teamId) { states { nodes { id name } } } }",
                variables: {teamId: $teamId}
            }')")
        
        STATE_ID=$(echo "$STATES_RESPONSE" | jq -r --arg name "$ARGS" \
            '.data.team.states.nodes[] | select(.name | ascii_downcase == ($name | ascii_downcase)) | .id')
        
        if [ -z "$STATE_ID" ] || [ "$STATE_ID" == "null" ]; then
            echo "❌ State '$ARGS' not found. Available states:"
            echo "$STATES_RESPONSE" | jq -r '.data.team.states.nodes[].name'
            exit 1
        fi
        
        MUTATION='
        mutation UpdateIssue($issueId: String!, $stateId: String!) {
          issueUpdate(id: $issueId, input: { stateId: $stateId }) {
            success
          }
        }
        '
        
        RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n --arg query "$MUTATION" --arg issueId "$ISSUE_ID" --arg stateId "$STATE_ID" \
                '{query: $query, variables: {issueId: $issueId, stateId: $stateId}}')")
        
        if echo "$RESPONSE" | jq -e '.data.issueUpdate.success' > /dev/null; then
            echo "✅ Status updated to '$ARGS'"
        else
            echo "❌ Failed to update status"
            echo "$RESPONSE" | jq '.'
        fi
        ;;
        
    complete)
        # Find the "Done" or "Completed" state
        TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")
        STATES_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n --arg teamId "$TEAM_ID" '{
                query: "query($teamId: String!) { team(id: $teamId) { states { nodes { id name type } } } }",
                variables: {teamId: $teamId}
            }')")
        
        STATE_ID=$(echo "$STATES_RESPONSE" | jq -r \
            '.data.team.states.nodes[] | select(.type == "completed") | .id' | head -1)
        
        if [ -z "$STATE_ID" ] || [ "$STATE_ID" == "null" ]; then
            echo "❌ No completed state found"
            exit 1
        fi
        
        MUTATION='
        mutation UpdateIssue($issueId: String!, $stateId: String!) {
          issueUpdate(id: $issueId, input: { stateId: $stateId }) {
            success
          }
        }
        '
        
        RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $API_KEY" \
            -d "$(jq -n --arg query "$MUTATION" --arg issueId "$ISSUE_ID" --arg stateId "$STATE_ID" \
                '{query: $query, variables: {issueId: $issueId, stateId: $stateId}}')")
        
        if echo "$RESPONSE" | jq -e '.data.issueUpdate.success' > /dev/null; then
            echo "✅ Task marked complete"
        else
            echo "❌ Failed to complete task"
            echo "$RESPONSE" | jq '.'
        fi
        ;;
        
    *)
        echo "❌ Unknown action: $ACTION"
        echo "Valid actions: status, comment, complete"
        exit 1
        ;;
esac
