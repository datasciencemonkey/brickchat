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
from fastapi.responses import JSONResponse
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
    router_metadata: Optional[str] = None
    status: Optional[str] = None


class AgentResponse(BaseModel):
    agent_id: str
    endpoint_url: str
    name: str
    description: Optional[str] = None
    databricks_metadata: Dict[str, Any] = {}
    admin_metadata: Dict[str, Any] = {}
    router_metadata: Optional[str] = None
    status: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None



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
        "router_metadata": agent.get("router_metadata"),
        "status": agent["status"],
        "created_at": agent["created_at"].isoformat() if agent.get("created_at") else None,
        "updated_at": agent["updated_at"].isoformat() if agent.get("updated_at") else None,
    }


# ============ Discovery ============

@router.post("/discover", response_model=DiscoveryResponse)
async def discover_agents(user: UserContext = Depends(require_admin)):
    """
    Discover Agent Bricks from Databricks serving endpoints.

    Fetches serving endpoints with task="agent/v1/responses", generates agent IDs,
    and merges with existing registry. New endpoints get status='new', existing ones keep their status.
    """
    logger.info(f"Agent discovery triggered by {user.user_id}")

    discovered_endpoints = []

    # Use REST API directly to get task field (SDK doesn't expose it)
    import requests
    from urllib.parse import urlparse

    # Derive workspace host
    workspace_host = os.getenv("DATABRICKS_HOST", "")
    if not workspace_host and DATABRICKS_BASE_URL:
        workspace_host = DATABRICKS_BASE_URL.replace("/serving-endpoints", "")

    # Get token (prefer user token, fallback to app token)
    token = user.access_token if user.access_token else DATABRICKS_TOKEN

    if workspace_host and token:
        try:
            # Call REST API directly
            api_url = f"{workspace_host}/api/2.0/serving-endpoints"
            headers = {"Authorization": f"Bearer {token}"}

            logger.info(f"Fetching endpoints from: {api_url}")
            response = requests.get(api_url, headers=headers, timeout=30)
            response.raise_for_status()

            data = response.json()
            endpoints = data.get("endpoints", [])

            for ep in endpoints:
                # Filter for agent endpoints by task type
                task = ep.get("task")
                if task != "agent/v1/responses":
                    logger.debug(f"Skipping non-agent endpoint: {ep.get('name')} (task={task})")
                    continue

                endpoint_name = ep.get("name")
                endpoint_url = f"{workspace_host}/serving-endpoints/{endpoint_name}/invocations"

                discovered_endpoints.append({
                    "endpoint_url": endpoint_url,
                    "name": endpoint_name,
                    "description": ep.get("description") or f"Agent Brick: {endpoint_name}",
                    "databricks_metadata": {
                        "endpoint_name": endpoint_name,
                        "task": task,
                        "state": ep.get("state", {}).get("ready", "unknown"),
                        "creator": ep.get("creator"),
                        "id": ep.get("id"),
                    }
                })

                logger.info(f"Discovered agent endpoint: {endpoint_name}")

        except Exception as e:
            logger.error(f"Databricks discovery failed: {e}")
            # Continue with empty list - admin can still add manually
    else:
        logger.warning("No workspace host or token available - discovery will return empty results")

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

@router.get("")
async def get_enabled_agents(user: UserContext = Depends(get_current_user)):
    """Get all enabled agents (for router/chat use)."""
    agents = agents_db.get_enabled_agents()
    return JSONResponse(content=[serialize_agent(a) for a in agents])


@router.get("/all")
async def get_all_agents(user: UserContext = Depends(require_admin)):
    """Get all agents regardless of status (for admin UI)."""
    agents = agents_db.get_all_agents()
    result = [serialize_agent(a) for a in agents]
    # Use JSONResponse to bypass FastAPI's default serialization which may exclude None
    return JSONResponse(content=result)


@router.put("/{agent_id}")
async def update_agent(
    agent_id: str,
    update: AgentUpdateRequest = Body(...),
    user: UserContext = Depends(require_admin)
):
    """Update agent metadata or status."""
    logger.info(f"PUT /agents/{agent_id} received: name={update.name}, status={update.status}, router_metadata={repr(update.router_metadata)[:50]}")

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
        router_metadata=update.router_metadata,
        status=update.status
    )

    logger.info(f"DB update result: router_metadata={repr(updated.get('router_metadata') if updated else None)[:50]}")

    logger.info(f"Agent {agent_id} updated by {user.user_id}: status={update.status}, router_metadata={'set' if update.router_metadata else 'unchanged'}")

    return JSONResponse(content=serialize_agent(updated))


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
            yield f"data: {json.dumps({'done': True, 'thread_id': thread_id, 'user_message_id': user_msg_id, 'assistant_message_id': assistant_msg_id})}\n\n"

        except Exception as e:
            logger.error(f"Autonomous chat error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
        }
    )
