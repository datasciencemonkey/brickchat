# L3 Autonomous Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable users to converse with curated Agent Bricks through Claude-orchestrated intelligent routing.

**Architecture:** Backend Python router manages agent registry (PostgreSQL table) with discovery from Databricks, admin curation, and autonomous chat routing. Frontend Flutter uses Riverpod providers for autonomous mode state, admin settings UI for agent management, and chat UI enhancements for mode toggle and agent badges.

**Tech Stack:** Python FastAPI, PostgreSQL, Databricks SDK, Flutter/Dart, Riverpod state management

---

## Phase 1: Backend Foundation

### Task 1: Create Database Schema for Autonomous Agents

**Files:**
- Create: `backend/migrations/autonomous_agents.sql`
- Modify: `backend/database.py`

**Step 1: Create migration file**

Create `backend/migrations/autonomous_agents.sql`:

```sql
-- Autonomous Agents Registry Table
-- Stores curated Agent Bricks for L3 autonomous mode

CREATE TABLE IF NOT EXISTS autonomous_agents (
    agent_id VARCHAR(12) PRIMARY KEY,
    endpoint_url TEXT NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    databricks_metadata JSONB DEFAULT '{}',
    admin_metadata JSONB DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'new' CHECK (status IN ('enabled', 'disabled', 'new')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast status queries
CREATE INDEX IF NOT EXISTS idx_autonomous_agents_status ON autonomous_agents(status);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_autonomous_agents_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_autonomous_agents_updated ON autonomous_agents;
CREATE TRIGGER trigger_autonomous_agents_updated
    BEFORE UPDATE ON autonomous_agents
    FOR EACH ROW
    EXECUTE FUNCTION update_autonomous_agents_timestamp();
```

**Step 2: Run migration manually to verify**

```bash
cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/.worktrees/autonomous-mode/backend
# Connect to your PostgreSQL database and run the SQL
```

**Step 3: Add agent_id generation utility**

Add to `backend/database.py` after line 26 (after `normalize_unicode` function):

```python
import hashlib

def generate_agent_id(endpoint_url: str) -> str:
    """Generate deterministic 12-char ID from endpoint URL."""
    return hashlib.sha256(endpoint_url.encode()).hexdigest()[:12]
```

**Step 4: Add AutonomousAgentsDatabase class**

Add to `backend/database.py` after the `ChatDatabase` class:

```python
class AutonomousAgentsDatabase:
    """Database operations for autonomous agents registry."""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def get_agent_by_id(self, agent_id: str) -> Optional[Dict]:
        """Get a single agent by ID."""
        return self.db.execute_query_one(
            "SELECT * FROM autonomous_agents WHERE agent_id = %s",
            (agent_id,)
        )

    def get_agent_by_url(self, endpoint_url: str) -> Optional[Dict]:
        """Get a single agent by endpoint URL."""
        return self.db.execute_query_one(
            "SELECT * FROM autonomous_agents WHERE endpoint_url = %s",
            (endpoint_url,)
        )

    def get_enabled_agents(self) -> List[Dict]:
        """Get all enabled agents (for router)."""
        return self.db.execute_query(
            "SELECT * FROM autonomous_agents WHERE status = 'enabled' ORDER BY name"
        )

    def get_all_agents(self) -> List[Dict]:
        """Get all agents regardless of status (for admin UI)."""
        return self.db.execute_query(
            "SELECT * FROM autonomous_agents ORDER BY status, name"
        )

    def upsert_agent(
        self,
        agent_id: str,
        endpoint_url: str,
        name: str,
        description: Optional[str] = None,
        databricks_metadata: Optional[Dict] = None,
        admin_metadata: Optional[Dict] = None,
        status: str = 'new'
    ) -> Dict:
        """Insert or update an agent."""
        import json

        result = self.db.execute_query_one(
            """
            INSERT INTO autonomous_agents
                (agent_id, endpoint_url, name, description, databricks_metadata, admin_metadata, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (agent_id) DO UPDATE SET
                name = COALESCE(EXCLUDED.name, autonomous_agents.name),
                description = COALESCE(EXCLUDED.description, autonomous_agents.description),
                databricks_metadata = COALESCE(EXCLUDED.databricks_metadata, autonomous_agents.databricks_metadata),
                updated_at = CURRENT_TIMESTAMP
            RETURNING *
            """,
            (
                agent_id,
                endpoint_url,
                name,
                description,
                json.dumps(databricks_metadata or {}),
                json.dumps(admin_metadata or {}),
                status
            )
        )
        return result

    def update_agent(
        self,
        agent_id: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        admin_metadata: Optional[Dict] = None,
        status: Optional[str] = None
    ) -> Optional[Dict]:
        """Update agent fields (admin operations)."""
        import json

        updates = []
        params = []

        if name is not None:
            updates.append("name = %s")
            params.append(name)
        if description is not None:
            updates.append("description = %s")
            params.append(description)
        if admin_metadata is not None:
            updates.append("admin_metadata = %s")
            params.append(json.dumps(admin_metadata))
        if status is not None:
            updates.append("status = %s")
            params.append(status)

        if not updates:
            return self.get_agent_by_id(agent_id)

        params.append(agent_id)

        return self.db.execute_query_one(
            f"UPDATE autonomous_agents SET {', '.join(updates)} WHERE agent_id = %s RETURNING *",
            tuple(params)
        )

    def delete_agent(self, agent_id: str) -> bool:
        """Remove an agent from registry."""
        result = self.db.execute_query_one(
            "DELETE FROM autonomous_agents WHERE agent_id = %s RETURNING agent_id",
            (agent_id,)
        )
        return result is not None
```

**Step 5: Add initialization helper**

Add to `backend/database.py` at the end of the file:

```python
def initialize_autonomous_database() -> AutonomousAgentsDatabase:
    """Initialize the autonomous agents database."""
    db_manager = DatabaseManager()
    return AutonomousAgentsDatabase(db_manager)
```

**Step 6: Commit**

```bash
git add backend/migrations/autonomous_agents.sql backend/database.py
git commit -m "feat(backend): add autonomous_agents table schema and database class"
```

---

### Task 2: Create Autonomous Router - Agent Management Endpoints

**Files:**
- Create: `backend/routers/autonomous.py`
- Modify: `backend/app.py`

**Step 1: Create the autonomous router**

Create `backend/routers/autonomous.py`:

```python
"""
Autonomous Mode Router - Agent Management & Discovery

Endpoints:
- POST /api/agents/discover - Trigger Databricks discovery
- GET /api/agents - Get enabled agents (for router)
- GET /api/agents/all - Get all agents (for admin UI)
- PUT /api/agents/{agent_id} - Update agent
- DELETE /api/agents/{agent_id} - Remove agent
"""

import os
import logging
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException, Body, Depends
from pydantic import BaseModel

from database import initialize_autonomous_database, generate_agent_id
from auth import get_current_user, UserContext

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/agents", tags=["autonomous"])

# Initialize database
agents_db = initialize_autonomous_database()

# Admin group from environment
ADMIN_USER_GROUP = os.getenv("ADMIN_USER_GROUP", "admins")


# ============ Pydantic Models ============

class AgentUpdateRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    admin_metadata: Optional[Dict[str, Any]] = None
    status: Optional[str] = None


class AgentResponse(BaseModel):
    agent_id: str
    endpoint_url: str
    name: str
    description: Optional[str]
    databricks_metadata: Dict[str, Any]
    admin_metadata: Dict[str, Any]
    status: str
    created_at: str
    updated_at: str


class DiscoveryResponse(BaseModel):
    discovered: int
    new_agents: int
    existing_agents: int
    agents: List[AgentResponse]


# ============ Helper Functions ============

def is_admin(user: UserContext) -> bool:
    """Check if user is in admin group.

    In production with Databricks Apps, this would check user groups.
    For now, we check if user has workspace client access or is dev_user.
    """
    # Dev mode: allow dev_user as admin
    if user.user_id == "dev_user":
        return True

    # Production: user with access token can be admin
    # TODO: Implement proper group membership check via Databricks API
    if user.access_token:
        return True

    return False


def require_admin(user: UserContext = Depends(get_current_user)) -> UserContext:
    """Dependency that requires admin access."""
    if not is_admin(user):
        raise HTTPException(
            status_code=403,
            detail="Admin access required for this operation"
        )
    return user


def serialize_agent(agent: Dict) -> Dict:
    """Convert database row to API response format."""
    return {
        "agent_id": agent["agent_id"],
        "endpoint_url": agent["endpoint_url"],
        "name": agent["name"],
        "description": agent.get("description"),
        "databricks_metadata": agent.get("databricks_metadata") or {},
        "admin_metadata": agent.get("admin_metadata") or {},
        "status": agent["status"],
        "created_at": agent["created_at"].isoformat() if agent.get("created_at") else None,
        "updated_at": agent["updated_at"].isoformat() if agent.get("updated_at") else None,
    }


# ============ Discovery ============

@router.post("/discover", response_model=DiscoveryResponse)
async def discover_agents(user: UserContext = Depends(require_admin)):
    """
    Discover Agent Bricks from Databricks serving endpoints.

    Fetches all serving endpoints, generates agent IDs, and merges with existing registry.
    New endpoints get status='new', existing ones keep their status.
    """
    logger.info(f"Agent discovery triggered by {user.user_id}")

    discovered_endpoints = []

    # Try to get workspace client from user context
    workspace_client = user.get_workspace_client()

    if workspace_client:
        try:
            # Fetch serving endpoints from Databricks
            endpoints = workspace_client.serving_endpoints.list()

            for endpoint in endpoints:
                endpoint_name = endpoint.name
                # Construct endpoint URL
                # Format: https://<workspace-host>/serving-endpoints/<name>/invocations
                base_url = os.getenv("DATABRICKS_HOST", "")
                if base_url:
                    endpoint_url = f"{base_url}/serving-endpoints/{endpoint_name}/invocations"

                    discovered_endpoints.append({
                        "endpoint_url": endpoint_url,
                        "name": endpoint_name,
                        "description": getattr(endpoint, 'description', None) or f"Databricks serving endpoint: {endpoint_name}",
                        "databricks_metadata": {
                            "endpoint_name": endpoint_name,
                            "state": str(getattr(endpoint, 'state', {}).get('ready', 'unknown')),
                            "creator": getattr(endpoint, 'creator', None),
                        }
                    })
        except Exception as e:
            logger.error(f"Databricks discovery failed: {e}")
            # Continue with empty list - admin can still add manually
    else:
        logger.warning("No workspace client available - discovery will return empty results")

    # Process discovered endpoints
    new_count = 0
    existing_count = 0
    all_agents = []

    for ep in discovered_endpoints:
        agent_id = generate_agent_id(ep["endpoint_url"])
        existing = agents_db.get_agent_by_id(agent_id)

        if existing:
            existing_count += 1
            all_agents.append(serialize_agent(existing))
        else:
            new_count += 1
            agent = agents_db.upsert_agent(
                agent_id=agent_id,
                endpoint_url=ep["endpoint_url"],
                name=ep["name"],
                description=ep.get("description"),
                databricks_metadata=ep.get("databricks_metadata"),
                status="new"
            )
            all_agents.append(serialize_agent(agent))

    # Also include existing agents not in discovery (manually added or endpoint removed)
    existing_agents = agents_db.get_all_agents()
    existing_ids = {a["agent_id"] for a in all_agents}

    for agent in existing_agents:
        if agent["agent_id"] not in existing_ids:
            all_agents.append(serialize_agent(agent))

    logger.info(f"Discovery complete: {len(discovered_endpoints)} discovered, {new_count} new, {existing_count} existing")

    return DiscoveryResponse(
        discovered=len(discovered_endpoints),
        new_agents=new_count,
        existing_agents=existing_count,
        agents=all_agents
    )


# ============ Agent CRUD ============

@router.get("", response_model=List[AgentResponse])
async def get_enabled_agents(user: UserContext = Depends(get_current_user)):
    """Get all enabled agents (for router/chat use)."""
    agents = agents_db.get_enabled_agents()
    return [serialize_agent(a) for a in agents]


@router.get("/all", response_model=List[AgentResponse])
async def get_all_agents(user: UserContext = Depends(require_admin)):
    """Get all agents regardless of status (for admin UI)."""
    agents = agents_db.get_all_agents()
    return [serialize_agent(a) for a in agents]


@router.put("/{agent_id}", response_model=AgentResponse)
async def update_agent(
    agent_id: str,
    update: AgentUpdateRequest = Body(...),
    user: UserContext = Depends(require_admin)
):
    """Update agent metadata or status."""
    existing = agents_db.get_agent_by_id(agent_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Agent not found")

    # Validate status if provided
    if update.status and update.status not in ('enabled', 'disabled', 'new'):
        raise HTTPException(status_code=400, detail="Invalid status. Must be: enabled, disabled, new")

    updated = agents_db.update_agent(
        agent_id=agent_id,
        name=update.name,
        description=update.description,
        admin_metadata=update.admin_metadata,
        status=update.status
    )

    logger.info(f"Agent {agent_id} updated by {user.user_id}: status={update.status}")

    return serialize_agent(updated)


@router.delete("/{agent_id}")
async def delete_agent(
    agent_id: str,
    user: UserContext = Depends(require_admin)
):
    """Remove agent from registry."""
    existing = agents_db.get_agent_by_id(agent_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Agent not found")

    agents_db.delete_agent(agent_id)
    logger.info(f"Agent {agent_id} deleted by {user.user_id}")

    return {"status": "deleted", "agent_id": agent_id}
```

**Step 2: Register router in app.py**

Add import at top of `backend/app.py` (after line 21):

```python
from routers import autonomous
```

Add router registration (after line 65, after documents router):

```python
app.include_router(autonomous.router)
```

**Step 3: Commit**

```bash
git add backend/routers/autonomous.py backend/app.py
git commit -m "feat(backend): add autonomous router with agent management endpoints"
```

---

### Task 3: Create Autonomous Chat Endpoint

**Files:**
- Modify: `backend/routers/autonomous.py`

**Step 1: Add autonomous chat endpoint**

Add to the end of `backend/routers/autonomous.py`:

```python
# ============ Autonomous Chat ============

class AutonomousChatRequest(BaseModel):
    message: str
    conversation_history: Optional[List[Dict[str, str]]] = None
    thread_id: Optional[str] = None


class AutonomousChatResponse(BaseModel):
    response: str
    selected_agent: AgentResponse
    routing_reason: str
    thread_id: str
    citations: Optional[List[Dict]] = None


# Import OpenAI client setup
from openai import OpenAI

DATABRICKS_TOKEN = os.getenv("DATABRICKS_TOKEN", "")
DATABRICKS_BASE_URL = os.getenv("DATABRICKS_BASE_URL", "")
DATABRICKS_MODEL = os.getenv("DATABRICKS_MODEL", "")


def get_databricks_client() -> OpenAI:
    """Get OpenAI client for Databricks."""
    return OpenAI(
        api_key=DATABRICKS_TOKEN,
        base_url=DATABRICKS_BASE_URL
    )


def build_router_prompt(agents: List[Dict], user_message: str, conversation_history: List[Dict]) -> str:
    """Build the prompt for Claude to select an agent."""
    agent_descriptions = "\n".join([
        f"- **{a['name']}** (ID: {a['agent_id']}): {a.get('description', 'No description')}"
        for a in agents
    ])

    history_context = ""
    if conversation_history:
        recent = conversation_history[-4:]  # Last 2 exchanges
        history_context = "\n\nRecent conversation:\n" + "\n".join([
            f"{msg['role'].upper()}: {msg['content'][:200]}..."
            if len(msg['content']) > 200 else f"{msg['role'].upper()}: {msg['content']}"
            for msg in recent
        ])

    return f"""You are an intelligent router that selects the best agent to handle a user's request.

Available Agents:
{agent_descriptions}

User's current message: "{user_message}"
{history_context}

Based on the user's message and conversation context, select the SINGLE most appropriate agent.

Respond in this exact JSON format:
{{"agent_id": "<selected_agent_id>", "reason": "<brief explanation of why this agent is best suited>"}}

IMPORTANT:
- Only respond with the JSON, no other text
- The agent_id must be one of the IDs listed above
- Keep the reason concise (1-2 sentences)"""


@router.post("/chat/autonomous")
async def autonomous_chat(
    request: AutonomousChatRequest = Body(...),
    user: UserContext = Depends(get_current_user)
):
    """
    Route message through Claude orchestrator to selected agent.

    Flow:
    1. Fetch enabled agents
    2. Build router prompt
    3. Claude selects agent
    4. Forward to selected agent's endpoint
    5. Return response with agent metadata
    """
    import json
    from fastapi.responses import StreamingResponse
    from database import initialize_database

    chat_db = initialize_database()

    # Get enabled agents
    agents = agents_db.get_enabled_agents()
    if not agents:
        raise HTTPException(
            status_code=400,
            detail="No agents enabled for autonomous mode. Admin must enable at least one agent."
        )

    # If only one agent, skip routing
    if len(agents) == 1:
        selected_agent = agents[0]
        routing_reason = "Only one agent available"
    else:
        # Build router prompt and get Claude's selection
        router_prompt = build_router_prompt(
            agents,
            request.message,
            request.conversation_history or []
        )

        client = get_databricks_client()

        try:
            # Use chat completions for routing decision
            routing_response = client.chat.completions.create(
                model=DATABRICKS_MODEL,
                messages=[{"role": "user", "content": router_prompt}],
                max_tokens=200,
                temperature=0.1  # Low temperature for consistent routing
            )

            routing_text = routing_response.choices[0].message.content.strip()

            # Parse routing decision
            try:
                routing_decision = json.loads(routing_text)
                selected_id = routing_decision.get("agent_id")
                routing_reason = routing_decision.get("reason", "No reason provided")

                # Find the selected agent
                selected_agent = next(
                    (a for a in agents if a["agent_id"] == selected_id),
                    None
                )

                if not selected_agent:
                    # Fallback to first agent if routing fails
                    logger.warning(f"Router selected unknown agent {selected_id}, falling back to first")
                    selected_agent = agents[0]
                    routing_reason = f"Fallback: router selected unknown agent"

            except json.JSONDecodeError:
                logger.warning(f"Failed to parse routing response: {routing_text}")
                selected_agent = agents[0]
                routing_reason = "Fallback: could not parse routing decision"

        except Exception as e:
            logger.error(f"Routing error: {e}")
            selected_agent = agents[0]
            routing_reason = f"Fallback: routing error"

    # Create or get thread
    thread_id = request.thread_id
    if not thread_id:
        thread_id = chat_db.create_thread(
            user_id=user.user_id,
            metadata={"mode": "autonomous", "initial_agent": selected_agent["agent_id"]}
        )

    # Save user message
    user_msg_id = chat_db.save_message(
        thread_id=thread_id,
        user_id=user.user_id,
        message_role="user",
        message_content=request.message,
        agent_endpoint=selected_agent["endpoint_url"],
        metadata={"autonomous_mode": True}
    )

    # Forward to selected agent's endpoint
    agent_endpoint = selected_agent["endpoint_url"]

    def generate_stream():
        try:
            # Send routing metadata first
            yield f"data: {json.dumps({'routing': {'agent': serialize_agent(selected_agent), 'reason': routing_reason}})}\n\n"

            # Call the agent endpoint
            import requests

            agent_response = requests.post(
                agent_endpoint,
                headers={
                    "Authorization": f"Bearer {DATABRICKS_TOKEN}",
                    "Content-Type": "application/json"
                },
                json={
                    "messages": [
                        *[{"role": m["role"], "content": m["content"]}
                          for m in (request.conversation_history or [])],
                        {"role": "user", "content": request.message}
                    ]
                },
                stream=True,
                timeout=120
            )

            if agent_response.status_code != 200:
                yield f"data: {json.dumps({'error': f'Agent error: {agent_response.status_code}'})}\n\n"
                return

            full_response = ""

            for line in agent_response.iter_lines():
                if line:
                    line_text = line.decode('utf-8')
                    if line_text.startswith('data: '):
                        try:
                            data = json.loads(line_text[6:])
                            if 'choices' in data and data['choices']:
                                delta = data['choices'][0].get('delta', {})
                                content = delta.get('content', '')
                                if content:
                                    full_response += content
                                    yield f"data: {json.dumps({'content': content})}\n\n"
                        except json.JSONDecodeError:
                            continue

            # Save assistant message
            assistant_msg_id = chat_db.save_message(
                thread_id=thread_id,
                user_id=user.user_id,
                message_role="assistant",
                message_content=full_response,
                agent_endpoint=agent_endpoint,
                metadata={
                    "autonomous_mode": True,
                    "selected_agent_id": selected_agent["agent_id"],
                    "routing_reason": routing_reason
                }
            )

            # Send completion
            yield f"data: {json.dumps({'done': True, 'thread_id': thread_id, 'assistant_message_id': assistant_msg_id})}\n\n"

        except Exception as e:
            logger.error(f"Autonomous chat error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )
```

**Step 2: Add requests to requirements**

Verify `requests` is in requirements. If not, add it.

**Step 3: Commit**

```bash
git add backend/routers/autonomous.py
git commit -m "feat(backend): add autonomous chat endpoint with Claude routing"
```

---

## Phase 2: Frontend Foundation

### Task 4: Create Autonomous Mode Provider

**Files:**
- Create: `lib/features/autonomous/providers/autonomous_provider.dart`

**Step 1: Create the provider file**

Create directory and file:

```dart
// lib/features/autonomous/providers/autonomous_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for autonomous mode settings persistence
class AutonomousSettingsKeys {
  static const String autonomousModeEnabled = 'autonomous_mode_enabled';
  static const String lastSelectedAgentId = 'last_selected_agent_id';
}

/// Represents an Agent Brick from the backend
class AutonomousAgent {
  final String agentId;
  final String endpointUrl;
  final String name;
  final String? description;
  final Map<String, dynamic> databricksMetadata;
  final Map<String, dynamic> adminMetadata;
  final String status; // 'enabled', 'disabled', 'new'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AutonomousAgent({
    required this.agentId,
    required this.endpointUrl,
    required this.name,
    this.description,
    this.databricksMetadata = const {},
    this.adminMetadata = const {},
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory AutonomousAgent.fromJson(Map<String, dynamic> json) {
    return AutonomousAgent(
      agentId: json['agent_id'] ?? '',
      endpointUrl: json['endpoint_url'] ?? '',
      name: json['name'] ?? 'Unknown Agent',
      description: json['description'],
      databricksMetadata: json['databricks_metadata'] ?? {},
      adminMetadata: json['admin_metadata'] ?? {},
      status: json['status'] ?? 'new',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'agent_id': agentId,
    'endpoint_url': endpointUrl,
    'name': name,
    'description': description,
    'databricks_metadata': databricksMetadata,
    'admin_metadata': adminMetadata,
    'status': status,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  AutonomousAgent copyWith({
    String? agentId,
    String? endpointUrl,
    String? name,
    String? description,
    Map<String, dynamic>? databricksMetadata,
    Map<String, dynamic>? adminMetadata,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AutonomousAgent(
      agentId: agentId ?? this.agentId,
      endpointUrl: endpointUrl ?? this.endpointUrl,
      name: name ?? this.name,
      description: description ?? this.description,
      databricksMetadata: databricksMetadata ?? this.databricksMetadata,
      adminMetadata: adminMetadata ?? this.adminMetadata,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isEnabled => status == 'enabled';
  bool get isDisabled => status == 'disabled';
  bool get isNew => status == 'new';
}

/// Routing info attached to autonomous responses
class RoutingInfo {
  final AutonomousAgent agent;
  final String reason;

  RoutingInfo({required this.agent, required this.reason});

  factory RoutingInfo.fromJson(Map<String, dynamic> json) {
    return RoutingInfo(
      agent: AutonomousAgent.fromJson(json['agent'] ?? {}),
      reason: json['reason'] ?? 'No reason provided',
    );
  }
}

/// Provider for autonomous mode toggle state
final autonomousModeProvider = StateNotifierProvider<AutonomousModeNotifier, bool>((ref) {
  return AutonomousModeNotifier();
});

class AutonomousModeNotifier extends StateNotifier<bool> {
  AutonomousModeNotifier() : super(false) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(AutonomousSettingsKeys.autonomousModeEnabled) ?? false;
      state = enabled;
    } catch (e) {
      state = false;
    }
  }

  Future<void> setAutonomousMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AutonomousSettingsKeys.autonomousModeEnabled, enabled);
      state = enabled;
    } catch (e) {
      // If save fails, don't update state
    }
  }

  void toggle() {
    setAutonomousMode(!state);
  }
}

/// Provider for the list of all agents (admin view)
final allAgentsProvider = StateNotifierProvider<AllAgentsNotifier, List<AutonomousAgent>>((ref) {
  return AllAgentsNotifier();
});

class AllAgentsNotifier extends StateNotifier<List<AutonomousAgent>> {
  AllAgentsNotifier() : super([]);

  void setAgents(List<AutonomousAgent> agents) {
    state = agents;
  }

  void updateAgent(AutonomousAgent updated) {
    state = state.map((a) => a.agentId == updated.agentId ? updated : a).toList();
  }

  void removeAgent(String agentId) {
    state = state.where((a) => a.agentId != agentId).toList();
  }

  void addAgent(AutonomousAgent agent) {
    if (!state.any((a) => a.agentId == agent.agentId)) {
      state = [...state, agent];
    }
  }
}

/// Provider for enabled agents only (for chat use)
final enabledAgentsProvider = Provider<List<AutonomousAgent>>((ref) {
  final allAgents = ref.watch(allAgentsProvider);
  return allAgents.where((a) => a.isEnabled).toList();
});

/// Provider to check if autonomous mode is available (at least one agent enabled)
final autonomousModeAvailableProvider = Provider<bool>((ref) {
  final enabledAgents = ref.watch(enabledAgentsProvider);
  return enabledAgents.isNotEmpty;
});

/// Extension methods for easy access
extension AutonomousModeRef on WidgetRef {
  bool get isAutonomousMode => watch(autonomousModeProvider);
  AutonomousModeNotifier get autonomousModeNotifier => read(autonomousModeProvider.notifier);

  List<AutonomousAgent> get allAgents => watch(allAgentsProvider);
  AllAgentsNotifier get allAgentsNotifier => read(allAgentsProvider.notifier);

  List<AutonomousAgent> get enabledAgents => watch(enabledAgentsProvider);
  bool get isAutonomousModeAvailable => watch(autonomousModeAvailableProvider);
}
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/providers/autonomous_provider.dart
git commit -m "feat(frontend): add autonomous mode provider with agent state management"
```

---

### Task 5: Create Autonomous API Service

**Files:**
- Create: `lib/features/autonomous/services/autonomous_service.dart`

**Step 1: Create the service file**

```dart
// lib/features/autonomous/services/autonomous_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../providers/autonomous_provider.dart';

/// Service for autonomous mode API calls
class AutonomousService {
  static String get baseUrl {
    if (kIsWeb) {
      return ''; // Same origin in production
    }
    return 'http://localhost:8000';
  }

  /// Discover agents from Databricks (admin only)
  static Future<Map<String, dynamic>> discoverAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/discover');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 403) {
        return {'error': 'Admin access required'};
      } else {
        return {'error': 'Discovery failed: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': 'Connection error: $e'};
    }
  }

  /// Get all agents (admin view)
  static Future<List<AutonomousAgent>> getAllAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/all');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => AutonomousAgent.fromJson(j)).toList();
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to fetch agents: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get enabled agents only (for router/chat)
  static Future<List<AutonomousAgent>> getEnabledAgents() async {
    try {
      final url = Uri.parse('$baseUrl/api/agents');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => AutonomousAgent.fromJson(j)).toList();
      } else {
        throw Exception('Failed to fetch enabled agents: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update agent (admin only)
  static Future<AutonomousAgent?> updateAgent(
    String agentId, {
    String? name,
    String? description,
    Map<String, dynamic>? adminMetadata,
    String? status,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/$agentId');

      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (adminMetadata != null) body['admin_metadata'] = adminMetadata;
      if (status != null) body['status'] = status;

      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return AutonomousAgent.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Agent not found');
      } else {
        throw Exception('Update failed: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete agent (admin only)
  static Future<bool> deleteAgent(String agentId) async {
    try {
      final url = Uri.parse('$baseUrl/api/agents/$agentId');
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Agent not found');
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Send message in autonomous mode (streaming)
  static Stream<Map<String, dynamic>> sendAutonomousMessage(
    String message, {
    List<Map<String, String>>? conversationHistory,
    String? threadId,
  }) async* {
    try {
      final url = Uri.parse('$baseUrl/api/agents/chat/autonomous');

      final requestBody = <String, dynamic>{
        'message': message,
      };
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        requestBody['conversation_history'] = conversationHistory;
      }
      if (threadId != null) {
        requestBody['thread_id'] = threadId;
      }

      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(requestBody);

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              try {
                final jsonStr = line.substring(6);
                final data = json.decode(jsonStr);

                if (data['error'] != null) {
                  yield {'error': data['error']};
                  return;
                } else if (data['done'] == true) {
                  yield {
                    'done': true,
                    'thread_id': data['thread_id'],
                    'assistant_message_id': data['assistant_message_id'],
                  };
                  return;
                } else if (data['routing'] != null) {
                  yield {'routing': data['routing']};
                } else if (data['content'] != null) {
                  yield {'content': data['content']};
                }
              } catch (e) {
                continue;
              }
            }
          }
        }
      } else if (streamedResponse.statusCode == 400) {
        yield {'error': 'No agents enabled for autonomous mode'};
      } else {
        yield {'error': 'Request failed: ${streamedResponse.statusCode}'};
      }
    } catch (e) {
      yield {'error': 'Connection error: $e'};
    }
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/services/autonomous_service.dart
git commit -m "feat(frontend): add autonomous mode API service"
```

---

## Phase 3: Admin UI

### Task 6: Create Agent Card Widget

**Files:**
- Create: `lib/features/autonomous/presentation/widgets/agent_card.dart`

**Step 1: Create the widget**

```dart
// lib/features/autonomous/presentation/widgets/agent_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/autonomous_provider.dart';
import '../../../../core/theme/app_colors.dart';

class AgentCard extends ConsumerStatefulWidget {
  final AutonomousAgent agent;
  final Function(String status) onStatusChange;
  final VoidCallback? onDelete;
  final Function(String name, String description)? onEdit;

  const AgentCard({
    super.key,
    required this.agent,
    required this.onStatusChange,
    this.onDelete,
    this.onEdit,
  });

  @override
  ConsumerState<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends ConsumerState<AgentCard> {
  bool _isExpanded = false;
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.agent.name);
    _descriptionController = TextEditingController(text: widget.agent.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AgentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agent.name != widget.agent.name) {
      _nameController.text = widget.agent.name;
    }
    if (oldWidget.agent.description != widget.agent.description) {
      _descriptionController.text = widget.agent.description ?? '';
    }
  }

  Color _getStatusColor() {
    switch (widget.agent.status) {
      case 'enabled':
        return Colors.green;
      case 'disabled':
        return Colors.grey;
      case 'new':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel() {
    switch (widget.agent.status) {
      case 'enabled':
        return 'Enabled';
      case 'disabled':
        return 'Disabled';
      case 'new':
        return 'New';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.agent.isEnabled
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : appColors.input.withValues(alpha: 0.3),
          width: widget.agent.isEnabled ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Agent icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: _getStatusColor(),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Name and status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.agent.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor().withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getStatusLabel(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _getStatusColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Enable/Disable toggle
                Switch(
                  value: widget.agent.isEnabled,
                  onChanged: (value) {
                    widget.onStatusChange(value ? 'enabled' : 'disabled');
                  },
                  activeTrackColor: theme.colorScheme.primary,
                ),
              ],
            ),
          ),

          // Description
          if (widget.agent.description != null && widget.agent.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                widget.agent.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.mutedForeground,
                ),
                maxLines: _isExpanded ? null : 2,
                overflow: _isExpanded ? null : TextOverflow.ellipsis,
              ),
            ),

          // Expand button
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(_isExpanded ? 'Less' : 'More'),
                  style: TextButton.styleFrom(
                    foregroundColor: appColors.mutedForeground,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
                const Spacer(),
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: widget.onDelete,
                    color: Colors.red.shade400,
                    tooltip: 'Remove agent',
                  ),
              ],
            ),
          ),

          // Expanded details
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _isEditing ? _buildEditForm() : _buildDetails(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Endpoint URL
        _buildDetailRow('Endpoint', widget.agent.endpointUrl, Icons.link),
        const SizedBox(height: 12),

        // Agent ID
        _buildDetailRow('Agent ID', widget.agent.agentId, Icons.fingerprint),
        const SizedBox(height: 12),

        // Created date
        if (widget.agent.createdAt != null)
          _buildDetailRow(
            'Created',
            _formatDate(widget.agent.createdAt!),
            Icons.calendar_today,
          ),

        const SizedBox(height: 16),

        // Edit button
        if (widget.onEdit != null)
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _isEditing = true;
              });
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit Details'),
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: appColors.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: appColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _nameController.text = widget.agent.name;
                  _descriptionController.text = widget.agent.description ?? '';
                });
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                widget.onEdit?.call(
                  _nameController.text,
                  _descriptionController.text,
                );
                setState(() {
                  _isEditing = false;
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/presentation/widgets/agent_card.dart
git commit -m "feat(frontend): add agent card widget for admin UI"
```

---

### Task 7: Add Autonomous Agents Section to Settings Page

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`

**Step 1: Add imports**

Add at top of `settings_page.dart`:

```dart
import '../../autonomous/providers/autonomous_provider.dart';
import '../../autonomous/services/autonomous_service.dart';
import '../../autonomous/presentation/widgets/agent_card.dart';
```

**Step 2: Add state variables**

Add to `_SettingsPageState` class:

```dart
bool _isDiscovering = false;
bool _isLoadingAgents = false;
```

**Step 3: Add initState to load agents**

Add or modify `initState`:

```dart
@override
void initState() {
  super.initState();
  _loadAgents();
}

Future<void> _loadAgents() async {
  setState(() => _isLoadingAgents = true);
  try {
    final agents = await AutonomousService.getAllAgents();
    ref.read(allAgentsProvider.notifier).setAgents(agents);
  } catch (e) {
    // Silently fail - user may not be admin
  } finally {
    setState(() => _isLoadingAgents = false);
  }
}
```

**Step 4: Add the autonomous agents section builder**

Add method to `_SettingsPageState`:

```dart
Widget _buildAutonomousAgentsSection() {
  final theme = Theme.of(context);
  final appColors = context.appColors;
  final agents = ref.allAgents;

  return _buildModernCard(
    context,
    icon: Icons.smart_toy,
    title: 'Autonomous Agents',
    subtitle: 'Manage Agent Bricks for autonomous mode',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // Discover button
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isDiscovering ? null : _discoverAgents,
              icon: _isDiscovering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isDiscovering ? 'Discovering...' : 'Discover Agents'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            if (_isLoadingAgents)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Agents count summary
        Text(
          '${agents.where((a) => a.isEnabled).length} enabled, '
          '${agents.where((a) => a.isNew).length} new, '
          '${agents.length} total',
          style: theme.textTheme.bodySmall?.copyWith(
            color: appColors.mutedForeground,
          ),
        ),

        const SizedBox(height: 16),

        // Agent cards
        if (agents.isEmpty && !_isLoadingAgents)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: appColors.input.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 48,
                  color: appColors.mutedForeground,
                ),
                const SizedBox(height: 12),
                Text(
                  'No agents discovered yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Click "Discover Agents" to find Databricks endpoints',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appColors.mutedForeground,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: agents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final agent = agents[index];
              return AgentCard(
                agent: agent,
                onStatusChange: (status) => _updateAgentStatus(agent.agentId, status),
                onDelete: () => _deleteAgent(agent.agentId),
                onEdit: (name, description) => _updateAgentDetails(
                  agent.agentId,
                  name: name,
                  description: description,
                ),
              );
            },
          ),
      ],
    ),
  );
}

Future<void> _discoverAgents() async {
  setState(() => _isDiscovering = true);
  try {
    final result = await AutonomousService.discoverAgents();
    if (result['error'] != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'])),
        );
      }
    } else {
      final agents = (result['agents'] as List)
          .map((j) => AutonomousAgent.fromJson(j))
          .toList();
      ref.read(allAgentsProvider.notifier).setAgents(agents);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Discovered ${result['discovered']} endpoints: '
              '${result['new_agents']} new, ${result['existing_agents']} existing',
            ),
          ),
        );
      }
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    }
  } finally {
    setState(() => _isDiscovering = false);
  }
}

Future<void> _updateAgentStatus(String agentId, String status) async {
  try {
    final updated = await AutonomousService.updateAgent(agentId, status: status);
    if (updated != null) {
      ref.read(allAgentsProvider.notifier).updateAgent(updated);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }
}

Future<void> _updateAgentDetails(
  String agentId, {
  String? name,
  String? description,
}) async {
  try {
    final updated = await AutonomousService.updateAgent(
      agentId,
      name: name,
      description: description,
    );
    if (updated != null) {
      ref.read(allAgentsProvider.notifier).updateAgent(updated);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }
}

Future<void> _deleteAgent(String agentId) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove Agent'),
      content: const Text('Are you sure you want to remove this agent from the registry?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirm == true) {
    try {
      await AutonomousService.deleteAgent(agentId);
      ref.read(allAgentsProvider.notifier).removeAgent(agentId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }
}
```

**Step 5: Add section to build method**

In the `build` method, add `_buildAutonomousAgentsSection()` after other sections (like TTS settings). Find the appropriate place in the Column children and add:

```dart
const SizedBox(height: 24),
_buildAutonomousAgentsSection(),
```

**Step 6: Commit**

```bash
git add lib/features/settings/presentation/settings_page.dart
git commit -m "feat(frontend): add autonomous agents management to settings page"
```

---

## Phase 4: Chat UI Integration

### Task 8: Create Autonomous Mode Toggle Widget

**Files:**
- Create: `lib/features/autonomous/presentation/widgets/autonomous_toggle.dart`

**Step 1: Create the widget**

```dart
// lib/features/autonomous/presentation/widgets/autonomous_toggle.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/autonomous_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Autonomous mode toggle with infinity animation
class AutonomousToggle extends ConsumerStatefulWidget {
  const AutonomousToggle({super.key});

  @override
  ConsumerState<AutonomousToggle> createState() => _AutonomousToggleState();
}

class _AutonomousToggleState extends ConsumerState<AutonomousToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final isAvailable = ref.isAutonomousModeAvailable;
    final isEnabled = ref.isAutonomousMode;

    // Don't show if no agents are enabled
    if (!isAvailable) {
      return const SizedBox.shrink();
    }

    // Control animation based on state
    if (isEnabled && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!isEnabled && _animationController.isAnimating) {
      _animationController.stop();
      _animationController.reset();
    }

    return GestureDetector(
      onTap: () {
        ref.autonomousModeNotifier.toggle();

        // Show feedback
        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Autonomous mode activated'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isEnabled
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : appColors.input.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : appColors.input.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Infinity symbol with animation
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: isEnabled ? _animationController.value * 0.5 : 0,
                  child: Text(
                    '∞',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isEnabled
                          ? theme.colorScheme.primary
                          : appColors.mutedForeground,
                    ),
                  ),
                )
                    .animate(target: isEnabled ? 1 : 0)
                    .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1))
                    .then()
                    .scale(begin: const Offset(1.1, 1.1), end: const Offset(1, 1));
              },
            ),
            const SizedBox(width: 6),
            Text(
              'Autonomous',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isEnabled
                    ? theme.colorScheme.primary
                    : appColors.mutedForeground,
                fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/presentation/widgets/autonomous_toggle.dart
git commit -m "feat(frontend): add autonomous mode toggle widget with infinity animation"
```

---

### Task 9: Create Agent Badge Widget

**Files:**
- Create: `lib/features/autonomous/presentation/widgets/agent_badge.dart`

**Step 1: Create the widget**

```dart
// lib/features/autonomous/presentation/widgets/agent_badge.dart

import 'package:flutter/material.dart';
import '../../providers/autonomous_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Badge showing which agent handled a message in autonomous mode
class AgentBadge extends StatefulWidget {
  final RoutingInfo routingInfo;
  final bool initiallyExpanded;

  const AgentBadge({
    super.key,
    required this.routingInfo,
    this.initiallyExpanded = false,
  });

  @override
  State<AgentBadge> createState() => _AgentBadgeState();
}

class _AgentBadgeState extends State<AgentBadge> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final agent = widget.routingInfo.agent;

    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: _isExpanded ? 12 : 8,
          vertical: _isExpanded ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(_isExpanded ? 12 : 16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact view: just agent name
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  agent.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ],
            ),

            // Expanded view: routing reason and details
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why this agent?',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appColors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.routingInfo.reason,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (agent.description != null && agent.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'About',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: appColors.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        agent.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appColors.mutedForeground,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/presentation/widgets/agent_badge.dart
git commit -m "feat(frontend): add agent badge widget for routing transparency"
```

---

### Task 10: Integrate Autonomous Mode into Chat Page

**Files:**
- Modify: `lib/features/chat/presentation/chat_home_page.dart`

**Step 1: Add imports**

Add at top of file:

```dart
import '../../autonomous/providers/autonomous_provider.dart';
import '../../autonomous/services/autonomous_service.dart';
import '../../autonomous/presentation/widgets/autonomous_toggle.dart';
import '../../autonomous/presentation/widgets/agent_badge.dart';
```

**Step 2: Add state for routing info**

Add to `_ChatHomePageState`:

```dart
RoutingInfo? _lastRoutingInfo;
```

**Step 3: Add autonomous toggle to chat header**

Find where the chat header/app bar is built and add the `AutonomousToggle` widget. This will vary based on exact UI structure. Look for the Row or AppBar that contains chat controls and add:

```dart
const AutonomousToggle(),
const SizedBox(width: 8),
```

**Step 4: Modify send message to use autonomous mode when enabled**

Find the `_sendMessage` method and wrap the send logic to check autonomous mode:

```dart
Future<void> _sendMessage(String text) async {
  if (text.trim().isEmpty) return;

  final isAutonomous = ref.read(autonomousModeProvider);

  // Add user message to UI immediately
  // ... existing user message code ...

  if (isAutonomous) {
    await _sendAutonomousMessage(text);
  } else {
    // ... existing send logic ...
  }
}

Future<void> _sendAutonomousMessage(String text) async {
  final streamResults = ref.read(streamResultsProvider);

  String fullResponse = '';
  RoutingInfo? routingInfo;

  try {
    await for (final chunk in AutonomousService.sendAutonomousMessage(
      text,
      conversationHistory: _conversationHistory,
      threadId: _currentThreadId,
    )) {
      if (chunk['error'] != null) {
        // Handle error
        _addAssistantMessage('Error: ${chunk['error']}');
        return;
      }

      if (chunk['routing'] != null) {
        routingInfo = RoutingInfo.fromJson(chunk['routing']);
        setState(() {
          _lastRoutingInfo = routingInfo;
        });
      }

      if (chunk['content'] != null) {
        fullResponse += chunk['content'];
        if (streamResults) {
          // Update streaming message
          _updateStreamingMessage(fullResponse);
        }
      }

      if (chunk['done'] == true) {
        _currentThreadId = chunk['thread_id'];
        if (!streamResults) {
          _addAssistantMessage(fullResponse, routingInfo: routingInfo);
        } else {
          _finalizeStreamingMessage(fullResponse, routingInfo: routingInfo);
        }

        // Update conversation history
        _conversationHistory.add({'role': 'user', 'content': text});
        _conversationHistory.add({'role': 'assistant', 'content': fullResponse});
      }
    }
  } catch (e) {
    _addAssistantMessage('Error: $e');
  }
}
```

**Step 5: Add agent badge to message display**

Find where assistant messages are rendered and add the agent badge when routing info is present. This depends on the chat UI structure but conceptually:

```dart
// In message bubble or after message content
if (message.metadata?['routingInfo'] != null)
  AgentBadge(
    routingInfo: RoutingInfo.fromJson(message.metadata!['routingInfo']),
  ),
```

**Step 6: Load enabled agents on init**

Add to `initState`:

```dart
_loadEnabledAgents();

// ...

Future<void> _loadEnabledAgents() async {
  try {
    final agents = await AutonomousService.getEnabledAgents();
    ref.read(allAgentsProvider.notifier).setAgents(agents);
  } catch (e) {
    // Silently fail - autonomous mode just won't be available
  }
}
```

**Step 7: Commit**

```bash
git add lib/features/chat/presentation/chat_home_page.dart
git commit -m "feat(frontend): integrate autonomous mode into chat UI"
```

---

## Phase 5: Final Integration & Testing

### Task 11: Export Autonomous Module

**Files:**
- Create: `lib/features/autonomous/autonomous.dart`

**Step 1: Create barrel export file**

```dart
// lib/features/autonomous/autonomous.dart

// Providers
export 'providers/autonomous_provider.dart';

// Services
export 'services/autonomous_service.dart';

// Widgets
export 'presentation/widgets/agent_card.dart';
export 'presentation/widgets/autonomous_toggle.dart';
export 'presentation/widgets/agent_badge.dart';
```

**Step 2: Commit**

```bash
git add lib/features/autonomous/autonomous.dart
git commit -m "feat(frontend): add autonomous module barrel export"
```

---

### Task 12: Manual Integration Testing

**Files:** None (testing task)

**Step 1: Start backend**

```bash
cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/.worktrees/autonomous-mode/backend
uv run python app.py
```

**Step 2: Build and run Flutter**

```bash
cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/.worktrees/autonomous-mode
flutter build web --wasm
```

**Step 3: Test scenarios**

1. **Admin agent discovery:**
   - Navigate to Settings
   - Find "Autonomous Agents" section
   - Click "Discover Agents"
   - Verify agents appear

2. **Enable/disable agents:**
   - Toggle agent status
   - Verify state persists

3. **Autonomous mode toggle:**
   - In chat, find autonomous toggle
   - Verify only visible if agents enabled
   - Toggle on, verify animation

4. **Autonomous chat:**
   - Send message in autonomous mode
   - Verify routing info appears
   - Verify agent badge on response

**Step 4: Fix any issues found**

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete L3 autonomous mode implementation"
```

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-3 | Backend: Database schema, agent management API, autonomous chat endpoint |
| 2 | 4-5 | Frontend foundation: Providers, API service |
| 3 | 6-7 | Admin UI: Agent cards, settings integration |
| 4 | 8-10 | Chat UI: Toggle, badge, chat integration |
| 5 | 11-12 | Final: Module export, integration testing |

**Total Tasks:** 12
**Estimated Commits:** 12+
