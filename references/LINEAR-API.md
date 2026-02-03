# Linear API Reference

Quick reference for Linear GraphQL API operations used by Apex Agents.

## Authentication

All requests require the API key in Authorization header:
```bash
curl -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: lin_api_xxx" \
  -d '{"query": "..."}'
```

## Common Queries

### Get Viewer (Current User)
```graphql
{
  viewer {
    id
    name
    email
  }
}
```

### List Teams
```graphql
{
  teams {
    nodes {
      id
      name
      key
    }
  }
}
```

### Get Team Issues
```graphql
query($teamId: String!) {
  team(id: $teamId) {
    issues(first: 50) {
      nodes {
        id
        identifier
        title
        description
        state { name type }
        assignee { name }
        createdAt
        updatedAt
      }
    }
  }
}
```

### Get Issue by ID
```graphql
query($id: String!) {
  issue(id: $id) {
    id
    identifier
    title
    description
    state { name }
    comments {
      nodes {
        body
        user { name }
        createdAt
      }
    }
  }
}
```

### Get Team States (Workflow)
```graphql
query($teamId: String!) {
  team(id: $teamId) {
    states {
      nodes {
        id
        name
        type
        position
      }
    }
  }
}
```

## Mutations

### Create Issue
```graphql
mutation($teamId: String!, $title: String!, $description: String) {
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
```

### Update Issue State
```graphql
mutation($issueId: String!, $stateId: String!) {
  issueUpdate(id: $issueId, input: { stateId: $stateId }) {
    success
  }
}
```

### Add Comment
```graphql
mutation($issueId: String!, $body: String!) {
  commentCreate(input: {
    issueId: $issueId
    body: $body
  }) {
    success
    comment { id }
  }
}
```

### Assign Issue
```graphql
mutation($issueId: String!, $assigneeId: String!) {
  issueUpdate(id: $issueId, input: { assigneeId: $assigneeId }) {
    success
  }
}
```

## Webhooks

Linear supports webhooks for real-time updates. Configure in:
Settings → API → Webhooks

Useful events:
- `Issue` - Created, updated, removed
- `Comment` - Created, updated
- `IssueLabel` - Added, removed

Webhook payload includes:
```json
{
  "action": "create",
  "type": "Issue",
  "data": { ... },
  "url": "https://linear.app/...",
  "createdAt": "..."
}
```

## Rate Limits

- 1500 requests per hour per API key
- Complex queries count as multiple requests
- Use pagination for large result sets

## Filtering Issues

Filter by state type:
```graphql
issues(filter: { state: { type: { eq: "started" } } })
```

State types: `backlog`, `unstarted`, `started`, `completed`, `canceled`

Filter by assignee:
```graphql
issues(filter: { assignee: { id: { eq: "user-id" } } })
```

Filter by label:
```graphql
issues(filter: { labels: { name: { eq: "urgent" } } })
```

## Pagination

Use cursor-based pagination:
```graphql
issues(first: 50, after: "cursor") {
  pageInfo {
    hasNextPage
    endCursor
  }
  nodes { ... }
}
```
