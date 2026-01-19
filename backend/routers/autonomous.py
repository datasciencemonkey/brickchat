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
