# Document Upload & Chat Design

**Date:** 2026-01-14
**Status:** Approved
**Feature:** Upload PDF/TXT files and chat with them using Claude

## Overview

Users can attach PDF or TXT files to their chat. When documents are present, the system automatically switches to Claude (via Databricks OpenAI-compatible endpoint) for document-aware responses. Documents persist in Databricks volumes and reload when users return to previous threads.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Flutter Frontend                                       │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Document Chips                                  │   │
│  │  ┌──────────┐ ┌──────────┐                      │   │
│  │  │report.pdf│ │data.txt  │                      │   │
│  │  └────✕─────┘ └────✕─────┘                      │   │
│  │                                                  │   │
│  │  Chat Input                                      │   │
│  │  [📎] [Type a message...                 ] [🎤][→]│   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  FastAPI Backend                                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │  POST /api/documents/upload                      │   │
│  │  GET  /api/documents/{thread_id}                 │   │
│  │  DELETE /api/documents/{thread_id}/{filename}    │   │
│  │  POST /api/chat/send (modified)                  │   │
│  └─────────────────────────────────────────────────┘   │
│                          │                              │
│            ┌─────────────┴─────────────┐               │
│            ▼                           ▼               │
│   No documents?              Documents present?        │
│   → DATABRICKS_MODEL         → CLAUDE_MODEL            │
│     (existing endpoint)        (Claude via Databricks) │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Databricks Volume Storage                              │
│  /Volumes/<catalog>/<schema>/documents/                 │
│  └── {user_id}/                                         │
│      └── {thread_id}/                                   │
│          ├── report.pdf                                 │
│          ├── data.txt                                   │
│          └── metadata.json                              │
└─────────────────────────────────────────────────────────┘
```

## User Flow

1. User clicks paperclip icon in chat input
2. File selector opens (PDF/TXT only)
3. Selected files appear as chips above input field
4. User can remove files with "x" on each chip
5. User types message and sends
6. Backend uploads files to volume, routes to Claude
7. Claude processes documents natively and responds
8. Subsequent messages in thread continue using Claude with document context
9. Starting new conversation clears documents and returns to normal endpoint

## Document Persistence & Reload

When a user returns to a previous thread with documents:

1. Backend checks if `/Volumes/.../documents/{user_id}/{thread_id}/` exists
2. If documents present, returns document metadata with messages
3. Frontend displays document chips and switches to Claude endpoint
4. User can continue chatting with full document context restored

## Limits

| Constraint | Value | Rationale |
|------------|-------|-----------|
| Max files per thread | 10 | Reasonable UX |
| Max file size | 10MB | Prevents memory issues |
| Allowed types | `.pdf`, `.txt` | Claude-supported formats |
| Max extracted text | 80K characters | Future limit if using extraction fallback |

## API Endpoints

### POST /api/documents/upload

Upload files and persist to volume.

**Request:**
```
Content-Type: multipart/form-data
- files: List[UploadFile]
- thread_id: Optional[str]  # Creates new thread if null
```

**Response:**
```json
{
  "thread_id": "abc-123",
  "documents": [
    {"filename": "report.pdf", "size": 245000, "status": "uploaded"},
    {"filename": "data.txt", "size": 12000, "status": "uploaded"}
  ],
  "total_size": 257000,
  "endpoint": "claude-opus-4-5"
}
```

### GET /api/documents/{thread_id}

List documents for a thread.

**Response:**
```json
{
  "documents": [
    {"filename": "report.pdf", "size": 245000, "uploaded_at": "2026-01-14T10:30:00Z"},
    {"filename": "data.txt", "size": 12000, "uploaded_at": "2026-01-14T10:30:05Z"}
  ]
}
```

### DELETE /api/documents/{thread_id}/{filename}

Remove a specific document from a thread.

### Modified: POST /api/chat/send

Existing endpoint enhanced to detect documents and route accordingly:

```python
if thread_has_documents(thread_id):
    # Load docs from volume, send to Claude API
    return stream_claude_response(message, documents, history)
else:
    # Existing behavior
    return stream_databricks_response(message, history)
```

### Modified: GET /api/chat/threads/{thread_id}/messages

Returns document metadata when thread has documents:

```json
{
  "messages": [...],
  "documents": [
    {"filename": "report.pdf", "size": 245000, "uploaded_at": "2026-01-14T10:30:00Z"}
  ]
}
```

## Environment Configuration

```bash
# Document storage (Databricks Volume)
DOCUMENTS_VOLUME_PATH=/Volumes/<catalog>/<schema>/documents

# Claude endpoint (Databricks OpenAI-compatible)
CLAUDE_BASE_URL=https://<workspace>.databricks.com/serving-endpoints
CLAUDE_MODEL=claude-opus-4-5
CLAUDE_TOKEN=<token>  # Could reuse DATABRICKS_TOKEN
```

## File Structure

### Backend (New/Modified)

```
backend/
├── routers/
│   ├── chat.py              # Modified - add document detection & Claude routing
│   ├── documents.py         # NEW - upload, list, delete endpoints
│   └── __init__.py          # Modified - export documents router
├── document_service.py      # NEW - volume storage, Claude API integration
└── app.py                   # Modified - register documents router
```

### Frontend (New/Modified)

```
lib/
├── features/
│   ├── chat/
│   │   └── presentation/
│   │       ├── chat_home_page.dart           # Modified - upload button, chips
│   │       └── widgets/
│   │           └── document_chip.dart        # NEW - removable document chip
│   └── settings/
│       └── providers/
│           └── documents_provider.dart       # NEW - document state management
└── core/
    └── services/
        └── fastapi_service.dart              # Modified - upload/document methods
```

## Implementation Order

1. **Backend: Document router & storage service**
   - Upload endpoint with volume persistence
   - List/delete endpoints
   - Validation logic (file type, size, count)

2. **Backend: Modify chat router**
   - Detect documents in thread
   - Route to Claude when documents present
   - Send files directly to Claude API (native PDF support)

3. **Frontend: Upload button & document chips**
   - Paperclip icon inside input field (left side)
   - Document chip widget with remove functionality
   - File selector integration (existing `file_selector` package)

4. **Frontend: State management**
   - Documents provider (Riverpod)
   - Auto-update endpoint display when documents present

5. **Frontend: Thread reload**
   - Load document metadata when opening previous thread
   - Restore chips and endpoint state

## Key Design Decisions

1. **Claude handles PDF natively** - No server-side extraction needed. Send raw files to Claude API.

2. **Implicit mode switching** - No "Agent Mode" toggle. Documents present = Claude endpoint automatically.

3. **Thread-scoped storage** - Documents tied to conversation. New thread clears everything.

4. **Volume persistence** - Documents survive sessions for audit and context reload.

5. **Future: Embedding fallback** - If extracted tokens exceed 80K, can add pgvector pipeline later.

## Future Enhancements

- Embedding pipeline for large documents (pgvector)
- Document preview in chat
- Support for additional file types (DOCX, images)
- Document search across threads
