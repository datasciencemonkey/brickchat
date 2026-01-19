# L3 Autonomous Mode Design

## Overview

BrickChat L3 Autonomous Mode enables users to converse with curated Agent Bricks through an intelligent routing system. Claude acts as the orchestrator, automatically selecting the appropriate agent based on user intent and available agent capabilities.

## Core Concepts

### Agent Bricks
- Databricks serving endpoints created via Agent Bricks (visual builder or custom code)
- Each brick is a deployed agent with its own endpoint URL
- Discovered from Databricks, curated by app admins

### Autonomous Mode
- User-facing toggle in chat UI (gated by admin enablement)
- Claude orchestrates routing between available agents per message
- Transparent routing with agent badges on responses

---

## Data Model

### `autonomous_agents` Table

| Column | Type | Description |
|--------|------|-------------|
| `agent_id` | VARCHAR(12) PK | SHA256 hash of endpoint URL (first 12 chars) |
| `endpoint_url` | TEXT | Full Databricks serving endpoint URL |
| `name` | VARCHAR(255) | Display name (from Databricks or admin override) |
| `description` | TEXT | What this agent does (from Databricks + admin enrichment) |
| `databricks_metadata` | JSONB | Raw metadata from Databricks discovery |
| `admin_metadata` | JSONB | Admin-added routing hints, tags, notes |
| `status` | ENUM | `enabled`, `disabled`, `new` |
| `created_at` | TIMESTAMP | When first discovered |
| `updated_at` | TIMESTAMP | Last modification |

### Agent ID Generation

```python
import hashlib

def generate_agent_id(endpoint_url: str) -> str:
    return hashlib.sha256(endpoint_url.encode()).hexdigest()[:12]
```

Deterministic, fixed-length, collision-resistant identifier for fast DB lookups.

---

## Backend API

### Agent Management Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/agents/discover` | POST | Triggers Databricks discovery, returns all endpoints with status |
| `/api/agents` | GET | Returns enabled agents only (for router) |
| `/api/agents/all` | GET | Returns all agents with status (for admin settings UI) |
| `/api/agents/{agent_id}` | PUT | Update agent metadata, status, admin enrichments |
| `/api/agents/{agent_id}` | DELETE | Remove agent from registry |

### Autonomous Chat Endpoint

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/chat/autonomous` | POST | Routes message through Claude orchestrator → selected agent |

**Autonomous chat flow:**
1. Fetch enabled agents from DB
2. Build router prompt with agent names and descriptions
3. Claude selects appropriate agent
4. Forward message to selected agent's endpoint
5. Stream response back with agent badge metadata

### Discovery & Deduplication Flow

1. **Discover** - Fetch all serving endpoints from Databricks
2. **Hash** - Generate `agent_id` from each endpoint URL
3. **Match** - Compare against existing `agent_id` values in DB
4. **Merge** - Return unified list with status:
   - `enabled` - In DB, marked autonomous-ready
   - `disabled` - In DB, turned off
   - `new` - Discovered but not yet curated

---

## Frontend Components

### A. Admin Settings - Agent Management

**Location:** New section in Settings page

**Visibility:** Only visible if user is in admin group (group name from `ADMIN_USER_GROUP` env var)

**Components:**
- "Autonomous Agents" card section header
- "Discover Agents" button → triggers `/api/agents/discover`
- Grid of agent cards displaying:
  - Agent name and description
  - Status badge (Enabled / Disabled / New)
  - Toggle switch to enable/disable for autonomous mode
  - Expand button → edit panel for admin metadata enrichment

**Data source:** `/api/agents/all`

### B. Chat UI - Autonomous Mode Toggle

**Location:** Chat header area (near existing controls)

**Visibility conditions:**
- At least one agent is enabled by admin
- User has permission to use autonomous mode

**Behavior:**
- Toggle activates/deactivates autonomous mode for current session
- When activated:
  - Infinity (∞) animation plays as attention-grabbing indicator
  - "∞ Autonomous" label displays in chat header
- State managed via `autonomousModeProvider` (Riverpod)

### C. Message Display - Agent Badge

**On each autonomous response:**
- Small chip/badge showing agent name (e.g., "SQL Expert")
- Tap/click to expand details:
  - Routing reason (why this agent was selected)
  - Agent description
  - Full agent metadata

**Persistence:** Agent info stored in message metadata for conversation history

---

## Permissions Model

### Admin Access
- Controlled by user group membership
- Admin group name configured via `ADMIN_USER_GROUP` environment variable
- Admins can:
  - Trigger agent discovery
  - Enable/disable agents for autonomous mode
  - Edit agent metadata and routing hints

### User Access
- Autonomous mode toggle visible only if:
  - Admin has enabled at least one agent
  - User has permission (can be gated by user group if needed)

---

## User Experience Flow

### Admin Flow
1. Navigate to Settings → Autonomous Agents section
2. Click "Discover Agents" to fetch available endpoints from Databricks
3. Review discovered agents (cards show name, description, status)
4. Enable desired agents for autonomous mode via toggle
5. Optionally expand cards to add routing hints or notes

### User Flow
1. See autonomous mode toggle in chat UI (if enabled by admin)
2. Activate toggle → infinity animation plays, "∞ Autonomous" label appears
3. Send message → Claude routes to appropriate agent
4. Receive response with agent badge showing which agent handled it
5. Tap badge to see routing details
6. Continue conversation → Claude re-evaluates routing each turn

---

## Visual Design

### Autonomous Mode Indicators
- **Activation animation:** Infinity symbol animation (attention-grabbing)
- **Active state:** "∞ Autonomous" label in chat header
- **Response badge:** Small chip with agent name on each response

### Agent Cards (Admin Settings)
- Card-based layout matching existing settings page style
- Status badges:
  - Green for "Enabled"
  - Gray for "Disabled"
  - Blue for "New"
- Expandable for full metadata editing

---

## Future Considerations (Out of Scope)

- Router prompt design and optimization
- Thread model type integration with autonomous mode
- Multi-agent handoff patterns
- Usage analytics and routing metrics
- Agent health monitoring
