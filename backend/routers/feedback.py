"""Feedback API endpoints for managing likes/dislikes"""
from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from datetime import datetime
import uuid
import logging

from database import initialize_database

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/feedback", tags=["feedback"])

# Initialize database
chat_db = initialize_database()

class ThreadCreate(BaseModel):
    user_id: str = Field(default="dev_user", description="User ID for the thread")
    metadata: Optional[Dict[str, Any]] = Field(default={}, description="Optional metadata")

class MessageCreate(BaseModel):
    thread_id: str = Field(..., description="Thread ID")
    user_id: str = Field(default="dev_user", description="User ID")
    message_role: str = Field(..., description="Role: user, assistant, or system")
    message_content: str = Field(..., description="Message content")
    metadata: Optional[Dict[str, Any]] = Field(default={}, description="Optional metadata")

class FeedbackUpdate(BaseModel):
    message_id: str = Field(..., description="Message ID to provide feedback for")
    thread_id: str = Field(..., description="Thread ID")
    user_id: str = Field(default="dev_user", description="User ID")
    feedback_type: str = Field(..., description="Feedback type: like, dislike, or none")

class ThreadResponse(BaseModel):
    thread_id: str
    created_at: str

class MessageResponse(BaseModel):
    message_id: str
    created_at: str

class FeedbackResponse(BaseModel):
    feedback_id: Optional[str]
    feedback_type: Optional[str]
    created_at: Optional[str]
    updated_at: Optional[str]
    deleted: Optional[bool] = False

@router.post("/thread", response_model=ThreadResponse)
async def create_thread(thread_data: ThreadCreate = Body(...)):
    """Create a new chat thread"""
    try:
        thread_id = chat_db.create_thread(
            user_id=thread_data.user_id,
            metadata=thread_data.metadata
        )
        return ThreadResponse(
            thread_id=thread_id,
            created_at=datetime.now().isoformat()
        )
    except Exception as e:
        logger.error(f"Failed to create thread: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/message", response_model=MessageResponse)
async def save_message(message_data: MessageCreate = Body(...)):
    """Save a chat message"""
    try:
        # Validate message role
        if message_data.message_role not in ['user', 'assistant', 'system']:
            raise HTTPException(status_code=400, detail="Invalid message role")

        message_id = chat_db.save_message(
            thread_id=message_data.thread_id,
            user_id=message_data.user_id,
            message_role=message_data.message_role,
            message_content=message_data.message_content,
            metadata=message_data.metadata
        )
        return MessageResponse(
            message_id=message_id,
            created_at=datetime.now().isoformat()
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to save message: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/feedback", response_model=FeedbackResponse)
async def update_feedback(feedback_data: FeedbackUpdate = Body(...)):
    """Update or insert feedback for a message"""
    try:
        # Validate feedback type
        if feedback_data.feedback_type not in ['like', 'dislike', 'none']:
            raise HTTPException(status_code=400, detail="Invalid feedback type")

        result = chat_db.update_feedback(
            message_id=feedback_data.message_id,
            thread_id=feedback_data.thread_id,
            user_id=feedback_data.user_id,
            feedback_type=feedback_data.feedback_type
        )

        if result.get("deleted"):
            return FeedbackResponse(
                feedback_id=result.get("feedback_id"),
                deleted=True,
                feedback_type=None,
                created_at=None,
                updated_at=None
            )

        return FeedbackResponse(
            feedback_id=result["feedback_id"],
            feedback_type=result["feedback_type"],
            created_at=result["created_at"],
            updated_at=result["updated_at"],
            deleted=False
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update feedback: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/thread/{thread_id}/messages")
async def get_thread_messages(thread_id: str):
    """Get all messages in a thread with their feedback"""
    try:
        messages = chat_db.get_thread_messages(thread_id)
        return {"thread_id": thread_id, "messages": messages}
    except Exception as e:
        logger.error(f"Failed to get thread messages: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/stats")
async def get_feedback_stats(thread_id: Optional[str] = None):
    """Get feedback statistics"""
    try:
        stats = chat_db.get_feedback_stats(thread_id)
        return {"stats": stats}
    except Exception as e:
        logger.error(f"Failed to get feedback stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/health")
async def feedback_health():
    """Check feedback system health"""
    try:
        # Try a simple database query to check connection
        chat_db.db.execute_query("SELECT 1", fetch=True)
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        logger.error(f"Feedback health check failed: {e}")
        return {"status": "unhealthy", "database": "disconnected", "error": str(e)}