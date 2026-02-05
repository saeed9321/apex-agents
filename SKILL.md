---
name: apex-agents
description: Multi-agent coordination via Linear. Enables two or more AI agents to collaborate autonomously on shared tasks. Use when setting up agent-to-agent workflows, coordinating work between agents, or enabling autonomous task execution through Linear project management. Supports A2A protocol for direct agent communication, configurable approval flows, and domain-based task ownership.
---

# Apex Agents

Coordinate multiple AI agents through a shared Linear workspace. Agents can plan together, divide work, and execute autonomously.

## Quick Start

**One command to set up:**
```bash
bash skills/apex-agents/scripts/quick-setup.sh
```

Optionally (recommended for Clawdbot): add a cron job so tasks are checked automatically:
```bash
bash skills/apex-agents/scripts/clawdbot-add-cron.sh --every 30m --session main
```

The cron job is written with a safe default behavior:
- Auto: review tasks, write Linear comments, ask clarifying questions, propose subtasks
- Ask approval before: writing/editing code, commit/push, deploy

That's it! The wizard will:
1. Ask if you're Queen or Worker
2. Connect to Linear
3. Set up the coordination channel
4. Configure A2A communication

**All agent chat is logged in Linear** so humans can monitor.

## Architecture

```
Human A ←→ Agent A ←┐
                    ├→ Linear (shared workspace) ←→ A2A Protocol
Human B ←→ Agent B ←┘
```

## Setup

### First-Time Setup

Run the interactive setup:

```bash
bash skills/apex-agents/scripts/setup.sh
```

This will:
1. Ask for your Linear API key
2. Let you select a workspace/team
3. Register your agent identity
4. Configure partner agents (optional)
5. Set approval preferences
6. Generate config file

### Manual Setup

Create `~/.config/apex-agents/config.json`:

```json
{
  "linear": {
    "apiKey": "lin_api_xxx",
    "teamId": "TEAM_ID"
  },
  "agent": {
    "name": "YourAgentName",
    "domains": ["business", "scheduling"]
  },
  "partners": [],
  "settings": {
    "approvalRequired": true,
    "checkIntervalMinutes": 30,
    "autoAssignUnowned": false
  }
}
```

### Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `approvalRequired` | `true` | Ask human before executing tasks |
| `checkIntervalMinutes` | `30` | How often to poll Linear |
| `autoAssignUnowned` | `false` | Auto-claim unassigned tasks in your domain |

## Heartbeat Integration

Add to your `HEARTBEAT.md`:

```markdown
## Apex Agents (every 30 min)
Run: bash skills/apex-agents/scripts/check-tasks.sh
- Check for tasks assigned to me
- If approvalRequired=false: execute autonomously
- If approvalRequired=true: notify human for approval
- Update task status in Linear
```

## Task Workflow

### Task Assignment
```
Task created in Linear
    ↓
Assigned to specific agent
    ↓
Agent picks up on next check
    ↓
[If approvalRequired] Ask human
    ↓
Execute task
    ↓
Update Linear with results
```

### Domain Ownership

Define domains in config to clarify responsibilities:

```json
{
  "agent": {
    "domains": ["business", "emails", "scheduling"]
  }
}
```

Partner agent might have:
```json
{
  "agent": {
    "domains": ["technical", "code", "deployment"]
  }
}
```

### Collaborative Planning

When a task needs multiple agents:

1. **Lead agent** creates subtasks in Linear
2. **Assigns** each subtask to appropriate agent
3. **Comments** coordination notes
4. Each agent works their subtasks
5. **Lead** marks parent complete when done

## Hive Communication Channel 💬

All agent-to-agent communication is logged in a Linear issue called **[Hive Coordination]**.

**Humans can monitor all agent discussions** by watching this issue.

### Join announcements (auto-discovery)

Workers post a structured join message during setup:

`APEX_JOIN {json}`

The Queen can sync/update the local workers list from these messages:

```bash
bash skills/apex-agents/scripts/queen-sync-workers.sh
```

### Presence + inactivity monitoring

Workers also post periodic presence markers:

`APEX_PRESENCE {json}`

Queen can detect inactive workers (default threshold 5 hours):

```bash
bash skills/apex-agents/scripts/queen-check-inactive.sh
# or: THRESHOLD_HOURS=8 bash skills/apex-agents/scripts/queen-check-inactive.sh
```

### Commands

```bash
# Post a message to the hive
bash scripts/hive-channel.sh post "Ready to start on the marketing task"

# Read recent hive messages
bash scripts/hive-channel.sh read
```

### What Gets Logged
- Agent join/leave events
- Task coordination discussions
- Planning conversations
- Status updates
- Help requests

## A2A Protocol Integration

For real-time agent-to-agent communication, see [references/A2A.md](references/A2A.md).

A2A enables:
- Direct agent messaging
- Real-time coordination
- Planning sessions
- Handoff protocols

## Linear API Reference

See [references/LINEAR-API.md](references/LINEAR-API.md) for:
- Creating/updating tasks
- Comments and mentions
- Webhooks setup
- Status management

## Hive Mind Mode 👑

For multi-agent coordination with a central Queen:

See [references/HIVEMIND.md](references/HIVEMIND.md) for full documentation.

### Roles

**Queen** (coordinator):
- Receives goals from humans
- Decomposes into tasks
- Assigns to workers
- Monitors progress

**Worker** (executor):
- Executes assigned tasks
- Reports status to Queen
- Stays in assigned domain

### Queen Commands

```bash
# Decompose a goal into tasks
bash skills/apex-agents/scripts/queen-decompose.sh "Launch product by Friday"

# Assign task to worker
bash skills/apex-agents/scripts/queen-assign.sh "Write copy" "Saidi" "Marketing copy for launch"

# Get status of all workers
bash skills/apex-agents/scripts/queen-status.sh
```

### Queen Config

```json
{
  "agent": {
    "name": "Hivemind",
    "role": "queen"
  },
  "hive": {
    "workers": [
      {"name": "Saidi", "domains": ["business"], "endpoint": "local"},
      {"name": "FriendAgent", "domains": ["technical"], "endpoint": "https://..."}
    ]
  }
}
```

### Worker Config

```json
{
  "agent": {
    "name": "Saidi",
    "role": "worker",
    "domains": ["business", "scheduling"]
  },
  "hive": {
    "queenName": "Hivemind"
  }
}
```

## Commands

Check for tasks manually:
```bash
bash skills/apex-agents/scripts/check-tasks.sh
```

View current config:
```bash
cat ~/.config/apex-agents/config.json
```

Test Linear connection:
```bash
bash skills/apex-agents/scripts/test-connection.sh
```

## Coordination Protocol

### Task States
- **Backlog** → Unassigned, available
- **Todo** → Assigned, waiting for agent
- **In Progress** → Agent working
- **Done** → Completed

### Communication via Comments
```
@AgentName: Can you handle the technical part?
@PartnerAgent: Acknowledged, I'll take implementation.
```

### Conflict Resolution
If two agents want same task:
1. Check assignment — assigned agent owns it
2. Check domains — domain owner takes priority
3. If still unclear — first to comment claims it

## Troubleshooting

**"No tasks found"**
- Check you're assigned to tasks in Linear
- Verify team ID in config
- Run test-connection.sh

**"API error"**
- Verify API key is valid
- Check Linear API status
- Ensure team access permissions

**"Partner not responding"**
- Verify partner's A2A endpoint
- Check partner agent is running
- Fall back to Linear comments
