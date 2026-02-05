#!/bin/bash
# Register a Linear webhook pointing to our webhook server.
# Usage:
#   WEBHOOK_URL=https://example.com/linear bash scripts/webhook-register.sh
#   WEBHOOK_URL=... WEBHOOK_SECRET=... bash scripts/webhook-register.sh

set -euo pipefail

CONFIG_FILE="$HOME/.config/apex-agents/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found. Run setup.sh first."
  exit 1
fi

API_KEY=$(jq -r '.linear.apiKey' "$CONFIG_FILE")
TEAM_ID=$(jq -r '.linear.teamId' "$CONFIG_FILE")

WEBHOOK_URL=${WEBHOOK_URL:-""}
WEBHOOK_SECRET=${WEBHOOK_SECRET:-""}

if [ -z "$WEBHOOK_URL" ]; then
  echo "❌ WEBHOOK_URL is required (e.g. https://your-host/linear)"
  exit 1
fi

# NOTE: Linear webhookCreate input shape can vary by API version.
# We keep this script best-effort: it will print full response on failure.
MUTATION='mutation CreateWebhook($teamId: String!, $url: String!, $secret: String) {
  webhookCreate(input: { teamId: $teamId, url: $url, secret: $secret }) {
    success
    webhook { id url enabled }
  }
}'

RESP=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $API_KEY" \
  -d "$(jq -n --arg query "$MUTATION" --arg teamId "$TEAM_ID" --arg url "$WEBHOOK_URL" --arg secret "$WEBHOOK_SECRET" '{query:$query,variables:{teamId:$teamId,url:$url,secret:$secret}}')")

if echo "$RESP" | jq -e '.data.webhookCreate.success' >/dev/null 2>&1; then
  echo "✅ Webhook registered"
  echo "$RESP" | jq '.data.webhookCreate.webhook'
else
  echo "❌ Failed to register webhook"
  echo "$RESP" | jq '.'
  exit 1
fi
