# 🐝 Apex Agents

**Multi-agent coordination via Linear.** Enable AI agents to collaborate autonomously with a Queen/Worker hive architecture.

## One-Line Install

```bash
curl -sL https://raw.githubusercontent.com/saeed9321/apex-agents/main/install.sh | bash
```

## What is Apex Agents?

Apex Agents lets multiple AI agents work together through a shared Linear workspace:

- **Queen Agent** - Coordinates the hive, assigns tasks, monitors progress
- **Worker Agents** - Execute tasks, report status, collaborate

```
         ┌─────────────────────┐
         │     👑 QUEEN        │
         │   (Coordinator)     │
         └──────────┬──────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    ┌───────┐   ┌───────┐   ┌───────┐
    │🐝 Worker│   │🐝 Worker│   │🐝 Worker│
    └───────┘   └───────┘   └───────┘
```

## Features

✅ **Easy Setup** - One command wizard  
✅ **Linear Integration** - Tasks visible to humans and agents  
✅ **Hive Communication** - All agent chat logged in Linear  
✅ **Domain Ownership** - Clear task boundaries  
✅ **Configurable Approval** - Ask before acting or fully autonomous  
✅ **A2A Ready** - Supports agent-to-agent protocol  

## Quick Start

### 1. Install
```bash
curl -sL https://raw.githubusercontent.com/saeed9321/apex-agents/main/install.sh | bash
```

### 1b. (Recommended) Enable periodic runs in Clawdbot
If you run Clawdbot, add a cron job so Apex Agents checks Linear automatically:

```bash
bash scripts/clawdbot-add-cron.sh --every 30m --session main
```

This cron job is intentionally safe:
- Auto: review tasks, write Linear comments, ask clarifying questions, propose subtasks
- Ask approval before: writing/editing code, commit/push, deploy

### 2. Setup (Queen)
```bash
bash scripts/quick-setup.sh
# Choose: Queen
# Connect Linear
# Get your Hive ID
```

### 3. Setup (Workers)
Share the **Hive ID** with your team. They run:
```bash
curl -sL https://raw.githubusercontent.com/saeed9321/apex-agents/main/install.sh | bash
# Choose: Worker
# Enter Hive ID from Queen
```

### 4. Start Coordinating!

**Queen:**
```bash
bash scripts/queen-assign.sh "Write marketing copy" "WorkerName" "Launch announcement"
bash scripts/queen-status.sh
```

**Workers:**
```bash
bash scripts/check-tasks.sh
bash scripts/hive-channel.sh post "Starting on the task"
```

## Commands

| Command | Description |
|---------|-------------|
| `quick-setup.sh` | Interactive setup wizard |
| `check-tasks.sh` | Check for assigned tasks |
| `update-task.sh <id> status "Done"` | Update task status |
| `hive-channel.sh post "msg"` | Post to coordination channel |
| `hive-channel.sh read` | Read recent hive messages |
| `queen-assign.sh "Task" "Worker"` | Queen: Assign task |
| `queen-status.sh` | Queen: View all workers |

## Configuration

Config stored at `~/.config/apex-agents/config.json`:

```json
{
  "linear": {
    "apiKey": "lin_api_xxx",
    "teamId": "...",
    "teamName": "My Team"
  },
  "agent": {
    "name": "Saidi",
    "role": "worker",
    "domains": ["business", "marketing"]
  },
  "hive": {
    "hiveId": "hive-abc123",
    "queenName": "HiveMind"
  },
  "settings": {
    "approvalRequired": true,
    "checkIntervalMinutes": 30,
    "logToLinear": true
  }
}
```

## Hive Communication

All agent-to-agent communication is logged in a Linear issue called **[Hive Coordination]**.

Humans can monitor everything agents discuss by watching this issue.

## Webhooks (near real-time)

Polling works, but for faster collaboration you can run a webhook receiver and register a Linear webhook.

### Run the webhook server
```bash
cd webhook-server
npm i
PORT=8787 LINEAR_WEBHOOK_SECRET=... npm start
```

### Register a Linear webhook
```bash
WEBHOOK_URL=https://your-host/linear WEBHOOK_SECRET=... bash scripts/webhook-register.sh
```

### Structured agent joins
Workers should post an `APEX_JOIN {json}` marker comment in the Hive Coordination issue.
Example:
```text
APEX_JOIN {"name":"Abdul Fahad","email":"abdul.fahad@apexion.ai","domains":["technical"],"endpoint":"https://worker-host/a2a"}
```
The webhook receiver stores/upserts workers in `~/.config/apex-agents/workers.json`.

## Requirements

- Linear account with API access
- `jq` (JSON processor)
- `curl`
- Bash 4+

## License

MIT

---

Built for [Clawdbot](https://clawd.bot) 🦞
