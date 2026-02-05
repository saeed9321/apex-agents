#!/bin/bash
# Add (or suggest) Clawdbot cron jobs for Apex Agents.
# Requires: clawdbot CLI configured + running gateway.
#
# Usage:
#   bash scripts/clawdbot-add-cron.sh --every 30m --session main
#
# Notes:
# - This creates a system-event job that wakes the target session.
# - The job text is written to encourage a safe approval workflow:
#   do planning + Linear comments automatically, but ask before any code write/edit/commit/push/deploy.

set -euo pipefail

EVERY="30m"
SESSION="main"
TZ="Europe/Berlin"
AGENT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --every) EVERY="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --tz) TZ="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--every 30m] [--session main] [--tz Europe/Berlin] [--agent coder]";
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

JOB_NAME="Apex Agents: poll Linear tasks (${EVERY})"

SYSTEM_EVENT_TEXT=$(cat <<'EOF'
Apex-agents scheduled check: run `bash skills/apex-agents/scripts/check-tasks.sh`.

Do automatically (no approval needed):
- Fetch tasks assigned to the current Linear viewer
- Summarize status + next steps
- Ask clarifying questions for missing info
- Add/update comments in the relevant Linear issues
- Propose / decompose subtasks and suggest assignment

Approval required (ask Said before doing any of these):
- Write or modify any code files
- Commit / push to GitHub
- Deploy / run services that affect production
- Use or request secrets/tokens beyond what is already configured

If there are no tasks / nothing actionable, reply with NO_REPLY.
EOF
)

CMD=(clawdbot cron add --name "$JOB_NAME" --every "$EVERY" --tz "$TZ" --session "$SESSION" --system-event "$SYSTEM_EVENT_TEXT" --wake next-heartbeat)

if [ -n "$AGENT" ]; then
  CMD+=(--agent "$AGENT")
fi

echo "+ ${CMD[*]}"
"${CMD[@]}"
