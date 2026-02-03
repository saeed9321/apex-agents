# A2A Protocol Integration

Google's Agent-to-Agent (A2A) protocol enables direct communication between AI agents.

## Overview

A2A provides:
- **Discovery** - Find other agents
- **Authentication** - Verify agent identity
- **Messaging** - Direct agent-to-agent communication
- **Task Delegation** - Hand off work between agents

## When to Use A2A

| Use Case | Linear | A2A | Best Choice |
|----------|--------|-----|-------------|
| Task tracking | ✅ | ❌ | Linear |
| Human visibility | ✅ | ⚠️ | Linear |
| Real-time coordination | ❌ | ✅ | A2A |
| Planning discussions | ⚠️ | ✅ | A2A |
| Quick handoffs | ⚠️ | ✅ | A2A |

**Recommendation:** Use both. Linear for structured work, A2A for real-time agent chat.

## A2A Concepts

### Agent Card
Each agent publishes a "card" describing capabilities:
```json
{
  "name": "Saidi",
  "description": "Business and scheduling agent",
  "capabilities": ["task-execution", "scheduling", "email"],
  "endpoint": "https://agent.example.com/a2a"
}
```

### Messages
Agents exchange structured messages:
```json
{
  "type": "task-request",
  "from": "Saidi",
  "to": "PartnerAgent",
  "content": {
    "action": "review",
    "taskId": "ABC-123",
    "context": "Need technical review before deployment"
  }
}
```

### Task States
A2A tasks follow states:
- `pending` - Waiting for acceptance
- `accepted` - Agent took the task
- `working` - In progress
- `completed` - Done
- `rejected` - Agent declined

## Integration with Apex Agents

### Configuration

Add partner A2A endpoint to config:
```json
{
  "partners": [
    {
      "name": "PartnerAgent",
      "a2aEndpoint": "https://partner.example.com/a2a"
    }
  ]
}
```

### Handoff Protocol

When handing off work:

1. **Notify via A2A:**
```json
{
  "type": "task-handoff",
  "taskId": "ABC-123",
  "from": "Saidi",
  "to": "PartnerAgent",
  "context": "Finished spec, ready for implementation"
}
```

2. **Update Linear:**
- Add comment: "@PartnerAgent taking over implementation"
- Reassign issue if needed

3. **Partner acknowledges:**
```json
{
  "type": "task-accepted",
  "taskId": "ABC-123",
  "from": "PartnerAgent"
}
```

### Planning Session

For collaborative planning:

1. **Initiate session:**
```json
{
  "type": "planning-request",
  "topic": "Q2 roadmap",
  "participants": ["Saidi", "PartnerAgent"]
}
```

2. **Exchange ideas:**
```json
{
  "type": "planning-message",
  "sessionId": "plan-123",
  "content": "I suggest we prioritize feature X"
}
```

3. **Reach consensus:**
```json
{
  "type": "planning-decision",
  "sessionId": "plan-123",
  "decision": "Agreed on X, Y, Z priorities",
  "tasks": [
    {"title": "Implement X", "assignee": "Saidi"},
    {"title": "Implement Y", "assignee": "PartnerAgent"}
  ]
}
```

4. **Create Linear tasks from decisions**

## Implementation Status

A2A is still evolving. Current options:

1. **Full A2A** - When both agents support the protocol
2. **Simplified A2A** - Direct API calls between known agents
3. **Linear-mediated** - Use Linear comments as communication channel

### Simplified Direct Communication

If A2A isn't fully available, agents can communicate directly:

```bash
# Agent A notifies Agent B
curl -X POST https://agent-b.example.com/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Saidi",
    "type": "handoff",
    "taskId": "ABC-123",
    "message": "Ready for your review"
  }'
```

This requires:
- Known endpoints
- Shared authentication
- Agreed message format

## Future Roadmap

As A2A matures:
1. Standardized discovery
2. Verified agent identity
3. Capability negotiation
4. Multi-agent orchestration

For now, start with Linear as the coordination layer and add A2A for real-time communication as support becomes available.
