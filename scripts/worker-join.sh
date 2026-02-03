#!/bin/bash
# Apex Agents - Worker: announce join to the hive
# Posts a structured join marker to the Hive Coordination channel.
#
# Marker format (must start at beginning of comment body):
#   APEX_JOIN {json}

set -e

CONFIG_FILE="$HOME/.config/apex-agents/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found. Run setup.sh first."; exit 1
fi

ROLE=$(jq -r '.agent.role // "worker"' "$CONFIG_FILE")
if [ "$ROLE" != "worker" ]; then
  echo "❌ This command is for Worker only. Current role: $ROLE"; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HIVE_ID=$(jq -r '.hive.hiveId // empty' "$CONFIG_FILE")
NAME=$(jq -r '.agent.name' "$CONFIG_FILE")
DOMAINS=$(jq -c '.agent.domains // []' "$CONFIG_FILE")
ENDPOINT=$(jq -r '.agent.endpoint // "local"' "$CONFIG_FILE")

if [ -z "$HIVE_ID" ]; then
  echo "❌ Missing hive.hiveId in config."; exit 1
fi

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PAYLOAD=$(jq -n \
  --arg hiveId "$HIVE_ID" \
  --arg name "$NAME" \
  --arg role "worker" \
  --arg endpoint "$ENDPOINT" \
  --arg joinedAt "$NOW_ISO" \
  --argjson domains "$DOMAINS" \
  '{hiveId:$hiveId,name:$name,role:$role,domains:$domains,endpoint:$endpoint,joinedAt:$joinedAt}')

bash "$SCRIPT_DIR/hive-channel.sh" post "APEX_JOIN $PAYLOAD" >/dev/null

echo "✅ Joined hive: $HIVE_ID as worker $NAME"