# Document Upload & Chat Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable users to upload PDF/TXT files and chat with them using Claude, with automatic endpoint switching and document persistence.

**Architecture:** Flutter frontend with file chips in input field → FastAPI backend with document router → Databricks Volume storage → Claude API for document-aware responses. Documents persist per thread and reload on thread access.

**Tech Stack:** Flutter (file_selector, Riverpod), Python FastAPI, Databricks Volumes, Claude API (via OpenAI-compatible SDK)

---

## Implementation Progress

| Task | Status | Commit |
|------|--------|--------|
| 1. Create Document Service | ✅ Complete | `2a2822c` |
| 2. Create Documents Router | ✅ Complete | `014fad4` |
| 3. Register Documents Router | ✅ Complete | `60997ba` |
| 4. Modify Chat Router | ✅ Complete | `aad94cc` |
| 5. Thread Messages + Documents | ✅ Complete | `8f2549e` |
| 6. Document Chip Widget | ✅ Complete | `e36fa5e` |
| 7. Documents Provider | ✅ Complete | `98b410c` |
| 8. FastAPI Service Methods | ✅ Complete | `b925b30` |
| 9. Upload Button Integration | ✅ Complete | `9d34260` |
| 10. Endpoint Display Update | ✅ Complete | `d8e645e` |
| 11. Environment Variables | ✅ Complete | `c02bbba` |
| 12. Integration Test | ✅ Complete | Build verified |

---

## Task 1: Create Document Service (Backend Core) ✅

**Files:**
- Create: `backend/document_service.py`

**Step 1: Write the document service module**

```python
"""Document storage and Claude API service for BrickChat"""
import os
import json
import base64
import logging
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from openai import OpenAI

logger = logging.getLogger(__name__)

# Configuration from environment
DOCUMENTS_VOLUME_PATH = os.environ.get('DOCUMENTS_VOLUME_PATH', './documents')
CLAUDE_BASE_URL = os.environ.get('CLAUDE_BASE_URL', os.environ.get('DATABRICKS_BASE_URL', ''))
CLAUDE_MODEL = os.environ.get('CLAUDE_MODEL', 'claude-opus-4-5')
CLAUDE_TOKEN = os.environ.get('CLAUDE_TOKEN', os.environ.get('DATABRICKS_TOKEN', ''))

# Limits
MAX_FILES_PER_THREAD = 10
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'.pdf', '.txt'}


class DocumentService:
    """Handles document storage and Claude API integration"""

    def __init__(self):
        self._claude_client = None

    @property
    def claude_client(self) -> OpenAI:
        """Lazy-load Claude client"""
        if self._claude_client is None:
            self._claude_client = OpenAI(
                api_key=CLAUDE_TOKEN,
                base_url=CLAUDE_BASE_URL
            )
        return self._claude_client

    def get_thread_documents_path(self, user_id: str, thread_id: str) -> Path:
        """Get the path to a thread's document directory"""
        return Path(DOCUMENTS_VOLUME_PATH) / user_id / thread_id

    def validate_file(self, filename: str, size: int) -> Tuple[bool, str]:
        """Validate file against limits"""
        ext = Path(filename).suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            return False, f"File type '{ext}' not allowed. Allowed: {', '.join(ALLOWED_EXTENSIONS)}"
        if size > MAX_FILE_SIZE_BYTES:
            return False, f"File too large ({size} bytes). Max: {MAX_FILE_SIZE_BYTES} bytes"
        return True, ""

    def save_document(
        self,
        user_id: str,
        thread_id: str,
        filename: str,
        content: bytes
    ) -> Dict:
        """Save a document to the volume"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        doc_path.mkdir(parents=True, exist_ok=True)

        # Check existing document count
        existing_docs = self.list_documents(user_id, thread_id)
        if len(existing_docs) >= MAX_FILES_PER_THREAD:
            raise ValueError(f"Maximum {MAX_FILES_PER_THREAD} documents per thread exceeded")

        # Save the file
        file_path = doc_path / filename
        with open(file_path, 'wb') as f:
            f.write(content)

        # Update metadata
        metadata = self._load_metadata(user_id, thread_id)
        metadata['documents'] = metadata.get('documents', {})
        metadata['documents'][filename] = {
            'size': len(content),
            'uploaded_at': datetime.utcnow().isoformat() + 'Z',
            'content_type': 'application/pdf' if filename.endswith('.pdf') else 'text/plain'
        }
        self._save_metadata(user_id, thread_id, metadata)

        logger.info(f"Saved document {filename} for user {user_id}, thread {thread_id}")
        return {
            'filename': filename,
            'size': len(content),
            'status': 'uploaded'
        }

    def list_documents(self, user_id: str, thread_id: str) -> List[Dict]:
        """List all documents for a thread"""
        metadata = self._load_metadata(user_id, thread_id)
        docs = metadata.get('documents', {})
        return [
            {
                'filename': fname,
                'size': info.get('size', 0),
                'uploaded_at': info.get('uploaded_at', ''),
                'content_type': info.get('content_type', 'application/octet-stream')
            }
            for fname, info in docs.items()
        ]

    def delete_document(self, user_id: str, thread_id: str, filename: str) -> bool:
        """Delete a document from a thread"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        file_path = doc_path / filename

        if file_path.exists():
            file_path.unlink()

            # Update metadata
            metadata = self._load_metadata(user_id, thread_id)
            if filename in metadata.get('documents', {}):
                del metadata['documents'][filename]
                self._save_metadata(user_id, thread_id, metadata)

            logger.info(f"Deleted document {filename} for user {user_id}, thread {thread_id}")
            return True
        return False

    def thread_has_documents(self, user_id: str, thread_id: str) -> bool:
        """Check if a thread has any documents"""
        return len(self.list_documents(user_id, thread_id)) > 0

    def load_documents_for_claude(self, user_id: str, thread_id: str) -> List[Dict]:
        """Load documents formatted for Claude API"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        documents = self.list_documents(user_id, thread_id)
        result = []

        for doc in documents:
            file_path = doc_path / doc['filename']
            if file_path.exists():
                with open(file_path, 'rb') as f:
                    content = f.read()

                if doc['filename'].endswith('.pdf'):
                    # PDF: send as base64-encoded file
                    result.append({
                        'type': 'document',
                        'source': {
                            'type': 'base64',
                            'media_type': 'application/pdf',
                            'data': base64.b64encode(content).decode('utf-8')
                        }
                    })
                else:
                    # TXT: send as plain text
                    result.append({
                        'type': 'text',
                        'text': f"[Document: {doc['filename']}]\n\n{content.decode('utf-8')}"
                    })

        return result

    def _load_metadata(self, user_id: str, thread_id: str) -> Dict:
        """Load metadata.json for a thread"""
        metadata_path = self.get_thread_documents_path(user_id, thread_id) / 'metadata.json'
        if metadata_path.exists():
            with open(metadata_path, 'r') as f:
                return json.load(f)
        return {}

    def _save_metadata(self, user_id: str, thread_id: str, metadata: Dict):
        """Save metadata.json for a thread"""
        doc_path = self.get_thread_documents_path(user_id, thread_id)
        doc_path.mkdir(parents=True, exist_ok=True)
        metadata_path = doc_path / 'metadata.json'
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)


# Global instance
document_service = DocumentService()
```

**Step 2: Verify file created correctly**

Run: `ls -la backend/document_service.py`
Expected: File exists with ~200 lines

**Step 3: Commit**

```bash
git add backend/document_service.py
git commit -m "feat(backend): add document service for storage and Claude integration"
```

---

## Task 2: Create Documents Router (Backend API)

**Files:**
- Create: `backend/routers/documents.py`

**Step 1: Write the documents router**

```python
"""Documents router for upload, list, delete operations"""
from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Depends
from typing import List, Optional
import logging

from document_service import document_service, MAX_FILES_PER_THREAD, CLAUDE_MODEL
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
        "endpoint": CLAUDE_MODEL
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
```

**Step 2: Verify file created**

Run: `ls -la backend/routers/documents.py`
Expected: File exists

**Step 3: Commit**

```bash
git add backend/routers/documents.py
git commit -m "feat(backend): add documents router for upload/list/delete endpoints"
```

---

## Task 3: Register Documents Router in App

**Files:**
- Modify: `backend/app.py`
- Modify: `backend/routers/__init__.py`

**Step 1: Update routers/__init__.py**

Add to `backend/routers/__init__.py`:

```python
# Routers package
from . import documents
```

**Step 2: Update app.py to include documents router**

In `backend/app.py`, add import and include the router:

After line 10 (import routers):
```python
from routers import health, chat, tts, feedback, auth, documents
```

After line 62 (auth router):
```python
app.include_router(documents.router)
```

**Step 3: Verify syntax**

Run: `cd backend && uv run python -c "from app import app; print('OK')"`
Expected: `OK`

**Step 4: Commit**

```bash
git add backend/app.py backend/routers/__init__.py
git commit -m "feat(backend): register documents router in app"
```

---

## Task 4: Modify Chat Router for Document Detection

**Files:**
- Modify: `backend/routers/chat.py`

**Step 1: Add imports at top of chat.py**

After the existing imports (around line 11):
```python
from document_service import document_service, CLAUDE_MODEL as DOCUMENT_CLAUDE_MODEL
```

**Step 2: Add Claude streaming function**

Add this function before the `@router.post("/send")` endpoint (around line 190):

```python
async def stream_claude_with_documents(
    message: str,
    user_id: str,
    thread_id: str,
    conversation_history: List[dict]
):
    """Stream response from Claude with document context"""
    # Load documents for this thread
    doc_contents = document_service.load_documents_for_claude(user_id, thread_id)

    # Build messages array with documents
    messages = []

    # Add document context as first user message
    if doc_contents:
        doc_message_content = []
        for doc in doc_contents:
            doc_message_content.append(doc)
        doc_message_content.append({
            'type': 'text',
            'text': 'I have uploaded the above documents. Please use them to answer my questions.'
        })
        messages.append({
            'role': 'user',
            'content': doc_message_content
        })
        # Add assistant acknowledgment
        messages.append({
            'role': 'assistant',
            'content': 'I have received and reviewed the documents you uploaded. I will use them to answer your questions. What would you like to know?'
        })

    # Add conversation history
    for msg in conversation_history:
        messages.append({
            'role': msg.get('role', 'user'),
            'content': msg.get('content', '')
        })

    # Add current message
    messages.append({
        'role': 'user',
        'content': message
    })

    # Call Claude via document_service client
    client = document_service.claude_client
    response = client.chat.completions.create(
        model=DOCUMENT_CLAUDE_MODEL,
        messages=messages,
        stream=True
    )

    for chunk in response:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content
```

**Step 3: Modify send_message endpoint to detect documents**

In the `send_message` function, after extracting `thread_id` (around line 217), add document detection:

```python
        # Check if thread has documents - route to Claude if so
        has_documents = False
        if thread_id:
            has_documents = document_service.thread_has_documents(user_id, thread_id)

        if has_documents:
            # Route to Claude with documents
            return await _handle_document_chat(
                message_text=message_text,
                thread_id=thread_id,
                user_id=user_id,
                conversation_history=conversation_history,
                use_streaming=use_streaming
            )
```

**Step 4: Add document chat handler function**

Add this function after the `stream_claude_with_documents` function:

```python
async def _handle_document_chat(
    message_text: str,
    thread_id: str,
    user_id: str,
    conversation_history: List[dict],
    use_streaming: bool
):
    """Handle chat with document context via Claude"""
    # Save user message
    user_message_id = chat_db.save_message(
        thread_id=thread_id,
        user_id=user_id,
        message_role="user",
        message_content=message_text,
        agent_endpoint=DOCUMENT_CLAUDE_MODEL
    )

    if use_streaming:
        def generate_stream():
            try:
                # Send metadata first
                yield f"data: {json.dumps({'metadata': {'thread_id': thread_id, 'user_message_id': user_message_id, 'user_id': user_id, 'agent_endpoint': DOCUMENT_CLAUDE_MODEL}})}\n\n"

                full_response_parts = []

                # Stream from Claude
                for content in stream_claude_with_documents(
                    message=message_text,
                    user_id=user_id,
                    thread_id=thread_id,
                    conversation_history=conversation_history
                ):
                    full_response_parts.append(content)
                    yield f"data: {json.dumps({'content': content})}\n\n"

                # Save assistant message
                full_response = ''.join(full_response_parts)
                if full_response:
                    assistant_message_id = chat_db.save_message(
                        thread_id=thread_id,
                        user_id=user_id,
                        message_role="assistant",
                        message_content=full_response,
                        agent_endpoint=DOCUMENT_CLAUDE_MODEL
                    )
                    yield f"data: {json.dumps({'assistant_message_id': assistant_message_id})}\n\n"

                yield f"data: {json.dumps({'done': True})}\n\n"

            except Exception as e:
                logger.error(f"Document chat streaming error: {e}")
                yield f"data: {json.dumps({'error': str(e)})}\n\n"

        return StreamingResponse(
            generate_stream(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Access-Control-Allow-Origin": "*",
            }
        )
    else:
        # Non-streaming mode
        try:
            full_response_parts = []
            for content in stream_claude_with_documents(
                message=message_text,
                user_id=user_id,
                thread_id=thread_id,
                conversation_history=conversation_history
            ):
                full_response_parts.append(content)

            full_response = ''.join(full_response_parts)

            assistant_message_id = chat_db.save_message(
                thread_id=thread_id,
                user_id=user_id,
                message_role="assistant",
                message_content=full_response,
                agent_endpoint=DOCUMENT_CLAUDE_MODEL
            )

            return {
                "response": full_response,
                "citations": [],
                "backend": "claude",
                "thread_id": thread_id,
                "user_message_id": user_message_id,
                "assistant_message_id": assistant_message_id,
                "agent_endpoint": DOCUMENT_CLAUDE_MODEL,
                "status": "success"
            }
        except Exception as e:
            return {
                "response": f"Error: {str(e)}",
                "backend": "claude",
                "status": "error"
            }
```

**Step 5: Verify syntax**

Run: `cd backend && uv run python -c "from routers.chat import router; print('OK')"`
Expected: `OK`

**Step 6: Commit**

```bash
git add backend/routers/chat.py
git commit -m "feat(backend): add document detection and Claude routing to chat endpoint"
```

---

## Task 5: Modify Thread Messages to Include Documents

**Files:**
- Modify: `backend/routers/chat.py`

**Step 1: Update get_thread_messages endpoint**

Find the `get_thread_messages` function and modify its return to include documents:

```python
@router.get("/threads/{thread_id}/messages")
async def get_thread_messages(
    thread_id: str,
    limit: int = Query(default=None, ge=1, le=500, description="Maximum messages to return (default: all)"),
    offset: int = Query(default=0, ge=0, description="Number of messages to skip"),
    user: UserContext = Depends(get_current_user)
):
    """Get messages for a specific thread with optional pagination and document metadata"""
    try:
        messages = chat_db.get_thread_messages(thread_id, limit=limit, offset=offset)

        # Check for documents in this thread
        documents = document_service.list_documents(user.user_id, thread_id)

        return {
            "messages": messages,
            "limit": limit,
            "offset": offset,
            "documents": documents  # Include document metadata
        }
    except Exception as e:
        logger.error(f"Error fetching thread messages: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch messages: {str(e)}")
```

**Step 2: Commit**

```bash
git add backend/routers/chat.py
git commit -m "feat(backend): include document metadata in thread messages response"
```

---

## Task 6: Create Document Chip Widget (Frontend)

**Files:**
- Create: `lib/features/chat/presentation/widgets/document_chip.dart`

**Step 1: Write the document chip widget**

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// A chip widget representing an uploaded document with remove functionality
class DocumentChip extends StatelessWidget {
  final String filename;
  final int? size;
  final bool isLoading;
  final VoidCallback? onRemove;

  const DocumentChip({
    super.key,
    required this.filename,
    this.size,
    this.isLoading = false,
    this.onRemove,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon() {
    if (filename.toLowerCase().endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else if (filename.toLowerCase().endsWith('.txt')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? appColors.messageBubble.withValues(alpha: 0.6)
            : appColors.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appColors.sidebarBorder.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File icon
          Icon(
            _getFileIcon(),
            size: 16,
            color: appColors.accent,
          ),
          const SizedBox(width: 6),

          // Filename and size
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: appColors.messageText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (size != null)
                  Text(
                    _formatFileSize(size!),
                    style: TextStyle(
                      fontSize: 10,
                      color: appColors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Loading indicator or remove button
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: appColors.accent,
              ),
            )
          else if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: appColors.mutedForeground.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: appColors.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

**Step 2: Verify file created**

Run: `ls -la lib/features/chat/presentation/widgets/document_chip.dart`
Expected: File exists

**Step 3: Commit**

```bash
git add lib/features/chat/presentation/widgets/document_chip.dart
git commit -m "feat(flutter): add DocumentChip widget for displaying uploaded files"
```

---

## Task 7: Create Documents Provider (Frontend State)

**Files:**
- Create: `lib/features/chat/providers/documents_provider.dart`

**Step 1: Create the providers directory and file**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a document staged for upload or already uploaded
class StagedDocument {
  final String filename;
  final int size;
  final List<int>? bytes; // Raw bytes for upload (null if already uploaded)
  final bool isUploading;
  final String? uploadedAt;

  StagedDocument({
    required this.filename,
    required this.size,
    this.bytes,
    this.isUploading = false,
    this.uploadedAt,
  });

  bool get isUploaded => uploadedAt != null;

  StagedDocument copyWith({
    String? filename,
    int? size,
    List<int>? bytes,
    bool? isUploading,
    String? uploadedAt,
  }) {
    return StagedDocument(
      filename: filename ?? this.filename,
      size: size ?? this.size,
      bytes: bytes ?? this.bytes,
      isUploading: isUploading ?? this.isUploading,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

/// State notifier for managing staged and uploaded documents
class DocumentsNotifier extends StateNotifier<List<StagedDocument>> {
  DocumentsNotifier() : super([]);

  /// Add a new document to the staged list
  void addDocument(String filename, int size, List<int> bytes) {
    // Check if document with same name already exists
    if (state.any((doc) => doc.filename == filename)) {
      return; // Don't add duplicates
    }
    state = [...state, StagedDocument(filename: filename, size: size, bytes: bytes)];
  }

  /// Remove a document by filename
  void removeDocument(String filename) {
    state = state.where((doc) => doc.filename != filename).toList();
  }

  /// Mark a document as uploading
  void setUploading(String filename, bool isUploading) {
    state = state.map((doc) {
      if (doc.filename == filename) {
        return doc.copyWith(isUploading: isUploading);
      }
      return doc;
    }).toList();
  }

  /// Mark a document as uploaded
  void markUploaded(String filename, String uploadedAt) {
    state = state.map((doc) {
      if (doc.filename == filename) {
        return doc.copyWith(isUploading: false, uploadedAt: uploadedAt, bytes: null);
      }
      return doc;
    }).toList();
  }

  /// Load documents from backend response (for thread reload)
  void loadFromBackend(List<Map<String, dynamic>> documents) {
    state = documents.map((doc) => StagedDocument(
      filename: doc['filename'] ?? '',
      size: doc['size'] ?? 0,
      uploadedAt: doc['uploaded_at'],
    )).toList();
  }

  /// Clear all documents (for new conversation)
  void clear() {
    state = [];
  }

  /// Get documents that need to be uploaded
  List<StagedDocument> get pendingUploads =>
      state.where((doc) => !doc.isUploaded && !doc.isUploading).toList();

  /// Check if any documents are present
  bool get hasDocuments => state.isNotEmpty;

  /// Get total size of all documents
  int get totalSize => state.fold(0, (sum, doc) => sum + doc.size);
}

/// Provider for documents state
final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<StagedDocument>>((ref) {
  return DocumentsNotifier();
});

/// Computed provider: whether documents are present (for endpoint switching)
final hasDocumentsProvider = Provider<bool>((ref) {
  final documents = ref.watch(documentsProvider);
  return documents.isNotEmpty;
});

/// Computed provider: current endpoint based on document presence
final activeEndpointProvider = Provider<String?>((ref) {
  final hasDocuments = ref.watch(hasDocumentsProvider);
  // Return Claude model name when documents present, null otherwise (use default)
  return hasDocuments ? 'claude-opus-4-5' : null;
});
```

**Step 2: Verify file created**

Run: `ls -la lib/features/chat/providers/documents_provider.dart`
Expected: File exists

**Step 3: Commit**

```bash
git add lib/features/chat/providers/documents_provider.dart
git commit -m "feat(flutter): add documents provider for state management"
```

---

## Task 8: Add Upload Methods to FastAPI Service (Frontend)

**Files:**
- Modify: `lib/core/services/fastapi_service.dart`

**Step 1: Add document upload method**

Add these methods to the `FastApiService` class:

```dart
  /// Upload documents to the backend
  /// Returns thread_id and list of uploaded documents
  static Future<Map<String, dynamic>> uploadDocuments({
    required List<Map<String, dynamic>> files, // [{filename, bytes}]
    String? threadId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/documents/upload');

      var request = http.MultipartRequest('POST', url);

      // Add thread_id if provided
      if (threadId != null) {
        request.fields['thread_id'] = threadId;
      }

      // Add files
      for (final file in files) {
        request.files.add(http.MultipartFile.fromBytes(
          'files',
          file['bytes'] as List<int>,
          filename: file['filename'] as String,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'error': 'Upload failed: ${response.statusCode} - ${response.body}',
        };
      }
    } catch (e) {
      return {
        'error': 'Error uploading documents: $e',
      };
    }
  }

  /// Get documents for a thread
  static Future<List<Map<String, dynamic>>> getThreadDocuments(String threadId) async {
    try {
      final url = Uri.parse('$baseUrl/api/documents/$threadId');

      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['documents'] ?? []);
      } else {
        print('Error fetching documents: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching documents: $e');
      return [];
    }
  }

  /// Delete a document from a thread
  static Future<bool> deleteDocument(String threadId, String filename) async {
    try {
      final url = Uri.parse('$baseUrl/api/documents/$threadId/$filename');

      final response = await http.delete(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting document: $e');
      return false;
    }
  }
```

**Step 2: Verify syntax**

Run: `flutter analyze lib/core/services/fastapi_service.dart`
Expected: No new errors

**Step 3: Commit**

```bash
git add lib/core/services/fastapi_service.dart
git commit -m "feat(flutter): add document upload/list/delete methods to FastAPI service"
```

---

## Task 9: Add Upload Button to Chat Input (Frontend)

**Files:**
- Modify: `lib/features/chat/presentation/chat_home_page.dart`

**Step 1: Add imports at top of file**

```dart
import 'package:file_selector/file_selector.dart';
import '../providers/documents_provider.dart';
import 'widgets/document_chip.dart';
```

**Step 2: Add document chips display above input**

In the `_buildMessageInput()` method, add document chips display before the input row.

Find the comment `// Input row` and add before it:

```dart
          // Document chips (when files are staged/uploaded)
          Consumer(
            builder: (context, ref, _) {
              final documents = ref.watch(documentsProvider);
              if (documents.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: documents.map((doc) => DocumentChip(
                    filename: doc.filename,
                    size: doc.size,
                    isLoading: doc.isUploading,
                    onRemove: doc.isUploading ? null : () {
                      ref.read(documentsProvider.notifier).removeDocument(doc.filename);
                    },
                  )).toList(),
                ),
              );
            },
          ),
```

**Step 3: Add upload button inside TextField**

Modify the TextField decoration to include a prefix icon for upload:

```dart
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageInputFocus,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    prefixIcon: IconButton(
                      onPressed: _pickDocuments,
                      icon: Icon(
                        Icons.attach_file,
                        color: context.appColors.mutedForeground,
                      ),
                      tooltip: 'Attach document (PDF, TXT)',
                    ),
                    // ... rest of decoration
```

**Step 4: Add _pickDocuments method**

Add this method to the `_ChatHomePageState` class:

```dart
  Future<void> _pickDocuments() async {
    final typeGroup = XTypeGroup(
      label: 'Documents',
      extensions: ['pdf', 'txt'],
    );

    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    if (files.isEmpty) return;

    for (final file in files) {
      final bytes = await file.readAsBytes();
      final size = bytes.length;

      // Validate size (10MB limit)
      if (size > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${file.name} is too large (max 10MB)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }

      ref.read(documentsProvider.notifier).addDocument(
        file.name,
        size,
        bytes,
      );
    }
  }
```

**Step 5: Modify _sendMessage to upload documents first**

At the beginning of `_sendMessage`, add document upload logic:

```dart
  void _sendMessage({String? text}) async {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Upload any pending documents first
    final pendingDocs = ref.read(documentsProvider.notifier).pendingUploads;
    if (pendingDocs.isNotEmpty) {
      // Mark as uploading
      for (final doc in pendingDocs) {
        ref.read(documentsProvider.notifier).setUploading(doc.filename, true);
      }

      // Upload to backend
      final uploadResult = await FastApiService.uploadDocuments(
        files: pendingDocs.map((doc) => {
          'filename': doc.filename,
          'bytes': doc.bytes!,
        }).toList(),
        threadId: _currentThreadId,
      );

      if (uploadResult.containsKey('error')) {
        // Handle upload error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: ${uploadResult['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Reset uploading state
        for (final doc in pendingDocs) {
          ref.read(documentsProvider.notifier).setUploading(doc.filename, false);
        }
        return;
      }

      // Update thread ID if new
      _currentThreadId = uploadResult['thread_id'];

      // Mark documents as uploaded
      final uploadedDocs = uploadResult['documents'] as List<dynamic>? ?? [];
      for (final doc in uploadedDocs) {
        ref.read(documentsProvider.notifier).markUploaded(
          doc['filename'],
          DateTime.now().toIso8601String(),
        );
      }

      // Update endpoint display
      if (uploadResult['endpoint'] != null) {
        setState(() {
          _currentAgentEndpoint = uploadResult['endpoint'];
        });
      }
    }

    // ... rest of existing _sendMessage code
```

**Step 6: Modify _createNewThread to clear documents**

In the `_createNewThread` method, add:

```dart
      // Clear documents
      ref.read(documentsProvider.notifier).clear();
```

**Step 7: Modify _loadThreadConversation to load documents**

In the `_loadThreadConversation` method, after loading messages, add:

```dart
      // Load documents for this thread if any
      if (threadId != null) {
        final docs = await FastApiService.getThreadDocuments(threadId);
        ref.read(documentsProvider.notifier).loadFromBackend(docs);

        // Update endpoint if documents present
        if (docs.isNotEmpty) {
          _currentAgentEndpoint = 'claude-opus-4-5';
        }
      }
```

**Step 8: Verify syntax**

Run: `flutter analyze lib/features/chat/presentation/chat_home_page.dart`
Expected: No new errors (existing warnings OK)

**Step 9: Commit**

```bash
git add lib/features/chat/presentation/chat_home_page.dart
git commit -m "feat(flutter): add document upload button, chips, and integration with chat"
```

---

## Task 10: Update Agent Endpoint Display

**Files:**
- Modify: `lib/features/chat/presentation/chat_home_page.dart`

**Step 1: Update _buildAgentEndpointDisplay to show document count**

Modify the `_buildAgentEndpointDisplay` method:

```dart
  Widget _buildAgentEndpointDisplay() {
    final appColors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get document count from provider
    final documents = ref.watch(documentsProvider);
    final docCount = documents.length;

    // Get the endpoint name
    final endpointName = _currentAgentEndpoint ?? 'Unknown';

    // Build display text
    final displayText = docCount > 0
        ? 'Agent Endpoint: $endpointName • $docCount doc${docCount > 1 ? 's' : ''}'
        : 'Agent Endpoint: $endpointName';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? appColors.messageBubble.withValues(alpha: 0.6)
            : appColors.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: docCount > 0
              ? appColors.accent.withValues(alpha: 0.5)
              : appColors.sidebarBorder.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            docCount > 0 ? Icons.description : Icons.smart_toy_outlined,
            size: 13,
            color: docCount > 0
                ? appColors.accent
                : appColors.sidebarPrimary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 10.5,
              color: appColors.messageText.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
```

**Step 2: Commit**

```bash
git add lib/features/chat/presentation/chat_home_page.dart
git commit -m "feat(flutter): update endpoint display to show document count"
```

---

## Task 11: Add Environment Variables Documentation

**Files:**
- Modify: `backend/.env.example` (create if not exists)

**Step 1: Create or update .env.example**

```bash
# Existing Databricks config
DATABRICKS_TOKEN=your_databricks_token
DATABRICKS_BASE_URL=https://your-workspace.cloud.databricks.com/serving-endpoints
DATABRICKS_MODEL=your-model-endpoint

# Document storage (Databricks Volume)
DOCUMENTS_VOLUME_PATH=/Volumes/catalog/schema/documents

# Claude endpoint (for document chat)
CLAUDE_BASE_URL=https://your-workspace.cloud.databricks.com/serving-endpoints
CLAUDE_MODEL=claude-opus-4-5
CLAUDE_TOKEN=your_token  # Can be same as DATABRICKS_TOKEN

# Database
PGHOST=your-postgres-host
PGDATABASE=brickchat
PGUSER=service_brickchat
PG_PASS=your_password
PGPORT=5432
```

**Step 2: Commit**

```bash
git add backend/.env.example
git commit -m "docs: add environment variables for document upload feature"
```

---

## Task 12: Final Integration Test

**Step 1: Build Flutter app**

Run: `flutter build web --wasm`
Expected: Build succeeds

**Step 2: Start backend**

Run: `cd backend && uv run python app.py`
Expected: Server starts on port 8000

**Step 3: Test document upload flow**

1. Open http://localhost:8000
2. Click paperclip icon in chat input
3. Select a PDF or TXT file
4. Verify chip appears
5. Type a message and send
6. Verify response comes from Claude endpoint

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete document upload and chat feature

- Backend: document service, router, Claude integration
- Frontend: upload button, document chips, state management
- Auto-switches to Claude endpoint when documents present
- Documents persist in Databricks volumes per thread
- Thread reload restores document context"
```

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Backend | Document service (storage + Claude API) |
| 2 | Backend | Documents router (upload/list/delete) |
| 3 | Backend | Register router in app |
| 4 | Backend | Document detection in chat router |
| 5 | Backend | Include documents in thread messages |
| 6 | Frontend | DocumentChip widget |
| 7 | Frontend | Documents provider (state) |
| 8 | Frontend | FastAPI service upload methods |
| 9 | Frontend | Upload button and integration |
| 10 | Frontend | Endpoint display update |
| 11 | Docs | Environment variables |
| 12 | Test | Integration test |

**Total tasks:** 12
**Estimated time:** 2-3 hours for experienced developer
