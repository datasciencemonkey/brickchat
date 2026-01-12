"""Authentication router for debug and user info endpoints"""
from fastapi import APIRouter, Depends
from auth import get_current_user, UserContext
import logging

router = APIRouter(prefix="/api/auth", tags=["auth"])
logger = logging.getLogger(__name__)


@router.get("/me")
async def get_me(user: UserContext = Depends(get_current_user)):
    """
    Debug endpoint to verify authentication is working.

    Returns the current user's identity from Databricks Apps headers.
    When running locally, returns dev_user fallback.
    """
    result = {
        "user_id": user.user_id,
        "email": user.email,
        "username": user.username,
        "ip": user.ip,
        "authenticated": user.is_authenticated
    }

    # If authenticated, get full user info from Databricks
    if user.is_authenticated:
        try:
            w = user.get_workspace_client()
            if w:
                current_user = w.current_user.me()
                result["databricks_user"] = {
                    "id": current_user.id,
                    "user_name": current_user.user_name,
                    "display_name": current_user.display_name,
                    "active": current_user.active,
                    "groups_count": len(current_user.groups) if current_user.groups else 0,
                    "entitlements_count": len(current_user.entitlements) if current_user.entitlements else 0
                }
        except Exception as e:
            logger.error(f"Failed to get Databricks user info: {e}")
            result["databricks_error"] = str(e)

    return result
