#!/bin/bash
# Apex Agents - Worker: post presence heartbeat to the hive
# Posts a structured presence marker so the Queen can detect inactive workers.
#
# Marker format (must start at beginning of comment body):
#   APEX_PRESENCE {json}

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

if [ -z "$HIVE_ID" ]; then
  echo "❌ Missing hive.hiveId in config."; exit 1
fi

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOST=$(hostname 2>/dev/null || echo "unknown")

PAYLOAD=$(jq -n \
  --arg hiveId "$HIVE_ID" \
  --arg name "$NAME" \
  --arg role "worker" \
  --arg lastSeenAt "$NOW_ISO" \
  --arg host "$HOST" \
  '{hiveId:$hiveId,name:$name,role:$role,lastSeenAt:$lastSeenAt,host:$host}')

bash "$SCRIPT_DIR/hive-channel.sh" post "APEX_PRESENCE $PAYLOAD" >/dev/null

echo "✅ Presence posted: $NAME @ $NOW_ISO"