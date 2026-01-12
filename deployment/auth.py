"""Authentication module for Databricks Apps on-behalf-of user authentication"""
from fastapi import Request
from databricks.sdk import WorkspaceClient
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class UserContext:
    """Represents the authenticated user context from Databricks Apps headers"""

    def __init__(
        self,
        user_id: str,
        email: str,
        username: str,
        access_token: Optional[str] = None,
        ip: Optional[str] = None
    ):
        self.user_id = user_id
        self.email = email
        self.username = username
        self.access_token = access_token
        self.ip = ip
        self._workspace_client = None

    def get_workspace_client(self) -> Optional[WorkspaceClient]:
        """Get Databricks client with user's token for on-behalf-of calls"""
        if not self.access_token:
            return None
        if self._workspace_client is None:
            self._workspace_client = WorkspaceClient(
                token=self.access_token,
                auth_type="pat"
            )
        return self._workspace_client

    @property
    def is_authenticated(self) -> bool:
        """Check if user has a valid access token"""
        return self.access_token is not None

    def __repr__(self) -> str:
        return f"UserContext(user_id={self.user_id}, email={self.email}, authenticated={self.is_authenticated})"


async def get_current_user(request: Request) -> UserContext:
    """
    Extract user from Databricks Apps forwarded headers.

    When running in Databricks Apps, the following headers are available:
    - X-Forwarded-Email: User's email
    - X-Forwarded-Preferred-Username: Username
    - X-Forwarded-User: User identifier
    - X-Real-Ip: User's IP address
    - X-Forwarded-Access-Token: User's access token for API calls

    When running locally (not in Databricks Apps), falls back to dev_user.
    """
    headers = request.headers

    email = headers.get("X-Forwarded-Email")
    username = headers.get("X-Forwarded-Preferred-Username")
    user = headers.get("X-Forwarded-User")
    ip = headers.get("X-Real-Ip")
    access_token = headers.get("X-Forwarded-Access-Token")

    if access_token:
        user_id = user or username or email or "unknown"
        logger.info(f"Authenticated user: {user_id} (email: {email})")
        logger.info(f"User logged in: {user_id}")
        return UserContext(
            user_id=user_id,
            email=email or "",
            username=username or "",
            access_token=access_token,
            ip=ip
        )
    else:
        # Fallback for local development (not running in Databricks Apps)
        logger.debug("No forwarded token - using dev_user for local development")
        return UserContext(
            user_id="dev_user",
            email="dev@local",
            username="dev_user",
            access_token=None,
            ip=None
        )
