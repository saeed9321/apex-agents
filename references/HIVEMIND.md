# Hive Mind Architecture

The Queen/Worker model for multi-agent coordination.

## Roles

### Queen (Coordinator)
- Receives high-level goals from humans
- Decomposes into tasks
- Assigns work to workers
- Monitors progress
- Resolves blockers
- Reports results to humans

### Worker
- Executes assigned tasks
- Reports status to Queen
- Requests help when stuck
- Operates within assigned domain

## Configuration

### Queen Config
```json
{
  "agent": {
    "name": "Hivemind",
    "role": "queen"
  },
  "hive": {
    "workers": [
      {
        "name": "Saidi",
        "domains": ["business", "scheduling", "emails"],
        "endpoint": "local"
      },
      {
        "name": "FriendAgent",
        "domains": ["technical", "code", "deployment"],
        "endpoint": "https://friend-agent.example.com/a2a"
      }
    ]
  },
  "settings": {
    "approvalRequired": true,
    "autoDecompose": true,
    "workerTimeout": 3600
  }
}
```

### Worker Config
```json
{
  "agent": {
    "name": "Saidi",
    "role": "worker",
    "domains": ["business", "scheduling", "emails"]
  },
  "hive": {
    "queenName": "Hivemind",
    "queenEndpoint": "local",
    "reportInterval": 300
  },
  "settings": {
    "approvalRequired": false,
    "autoExecute": true
  }
}
```

## Communication Protocol

### Goal Submission (Human → Queen)
```
Human: "Launch product by Friday"
```

### Task Decomposition (Queen)
```json
{
  "goal": "Launch product by Friday",
  "tasks": [
    {
      "id": "task-1",
      "title": "Write marketing copy",
      "assignee": "Saidi",
      "domain": "business",
      "deadline": "2024-02-05",
      "dependencies": []
    },
    {
      "id": "task-2", 
      "title": "Deploy to production",
      "assignee": "FriendAgent",
      "domain": "technical",
      "deadline": "2024-02-06",
      "dependencies": ["task-1"]
    }
  ]
}
```

### Task Assignment (Queen → Worker)
```json
{
  "type": "task-assignment",
  "from": "Hivemind",
  "to": "Saidi",
  "task": {
    "id": "task-1",
    "title": "Write marketing copy",
    "description": "Create launch announcement...",
    "deadline": "2024-02-05",
    "context": "Product X launching Friday..."
  }
}
```

### Status Report (Worker → Queen)
```json
{
  "type": "status-report",
  "from": "Saidi",
  "to": "Hivemind",
  "task": "task-1",
  "status": "in_progress",
  "progress": 60,
  "notes": "Draft complete, reviewing...",
  "blockers": []
}
```

### Completion Report (Worker → Queen)
```json
{
  "type": "task-complete",
  "from": "Saidi",
  "to": "Hivemind",
  "task": "task-1",
  "result": {
    "summary": "Marketing copy ready",
    "deliverables": ["copy.md"],
    "notes": "Reviewed and approved"
  }
}
```

### Help Request (Worker → Queen)
```json
{
  "type": "help-request",
  "from": "FriendAgent",
  "to": "Hivemind",
  "task": "task-2",
  "issue": "Need API credentials from Saidi's domain",
  "suggestion": "Can Saidi provide access?"
}
```

### Coordination (Queen → Workers)
```json
{
  "type": "coordination",
  "from": "Hivemind",
  "to": "Saidi",
  "request": "FriendAgent needs API credentials for deployment",
  "context": "task-2 blocked",
  "action": "Please share credentials securely"
}
```

## Queen Responsibilities

### 1. Goal Intake
- Parse human requests
- Clarify ambiguities
- Confirm scope

### 2. Decomposition
- Break into atomic tasks
- Identify dependencies
- Estimate effort

### 3. Assignment
- Match tasks to worker domains
- Balance workload
- Set deadlines

### 4. Monitoring
- Track progress
- Detect blockers early
- Adjust assignments

### 5. Coordination
- Facilitate worker-to-worker needs
- Resolve conflicts
- Manage dependencies

### 6. Reporting
- Aggregate status
- Report to humans
- Escalate issues

## Worker Responsibilities

### 1. Execution
- Complete assigned tasks
- Stay within scope
- Meet deadlines

### 2. Reporting
- Regular status updates
- Immediate blocker alerts
- Completion notifications

### 3. Collaboration
- Respond to coordination requests
- Help other workers when asked
- Share relevant information

## Linear Integration

Tasks flow through Linear:

```
Queen creates parent issue
    └── Subtasks assigned to workers
        └── Workers update status
            └── Queen monitors via Linear
                └── Queen reports to humans
```

### Labels
- `queen-task` - Parent tasks from Queen
- `worker:saidi` - Assigned to Saidi
- `worker:friendagent` - Assigned to FriendAgent
- `blocked` - Needs attention
- `needs-coordination` - Cross-worker dependency

### Workflow States
- Backlog → Queen planning
- Todo → Assigned to worker
- In Progress → Worker executing
- Review → Worker done, Queen reviewing
- Done → Complete

## Failure Modes

### Worker Unresponsive
1. Queen detects missed check-ins
2. Queen alerts human
3. Human investigates or Queen reassigns

### Task Blocked
1. Worker reports blocker
2. Queen attempts resolution
3. Escalate to human if unresolved

### Conflicting Work
1. Queen detects overlap
2. Queen clarifies ownership
3. Merge or reassign as needed

### Human Override
Humans can always:
- Reassign tasks directly
- Cancel tasks
- Modify priorities
- Intervene in coordination
