"""Documents router for upload, list, delete operations"""
from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Depends
from typing import List, Optional
import logging
from dotenv import load_dotenv

# Load environment before importing modules that need it
load_dotenv()

from document_service import document_service, MAX_FILES_PER_THREAD, DATABRICKS_DOCUMENT_MODEL
from auth import get_current_user, UserContext
from database import initialize_database

router = APIRouter(prefix="/api/documents", tags=["documents"])
logger = logging.getLogger(__name__)

# Initialize database for thread creation
chat_db = initialize_database()


@router.post("/upload")
async def upload_documents(
    files: List[UploadFile] = File(...),
    thread_id: Optional[str] = Form(None),
    user: UserContext = Depends(get_current_user)
):
    """
    Upload one or more documents for a chat thread.
    Creates a new thread if thread_id is not provided.
    """
    user_id = user.user_id

    # Validate file count
    if len(files) > MAX_FILES_PER_THREAD:
        raise HTTPException(
            status_code=400,
            detail=f"Maximum {MAX_FILES_PER_THREAD} files allowed per upload"
        )

    # Create thread if not provided
    if not thread_id:
        thread_id = chat_db.create_thread(user_id=user_id, metadata={'has_documents': True})
        logger.info(f"Created new thread {thread_id} for document upload")

    uploaded_docs = []
    total_size = 0

    for file in files:
        # Read file content
        content = await file.read()

        # Validate file
        valid, error_msg = document_service.validate_file(file.filename, len(content))
        if not valid:
            raise HTTPException(status_code=400, detail=error_msg)

        # Save document
        try:
            doc_info = document_service.save_document(
                user_id=user_id,
                thread_id=thread_id,
                filename=file.filename,
                content=content
            )
            uploaded_docs.append(doc_info)
            total_size += len(content)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    return {
        "thread_id": thread_id,
        "documents": uploaded_docs,
        "total_size": total_size,
        "endpoint": DATABRICKS_DOCUMENT_MODEL
    }


@router.get("/{thread_id}")
async def list_documents(
    thread_id: str,
    user: UserContext = Depends(get_current_user)
):
    """List all documents for a thread"""
    documents = document_service.list_documents(user.user_id, thread_id)
    return {"documents": documents}


@router.delete("/{thread_id}/{filename}")
async def delete_document(
    thread_id: str,
    filename: str,
    user: UserContext = Depends(get_current_user)
):
    """Delete a specific document from a thread"""
    success = document_service.delete_document(user.user_id, thread_id, filename)
    if not success:
        raise HTTPException(status_code=404, detail="Document not found")
    return {"status": "deleted", "filename": filename}
