# Persist Upload Chips Across Conversations

## Problem

Document upload chips vanish when navigating away from a thread. When returning to a thread with documents, the chips should be reconstructed to show the user which documents are attached.

Currently:
- Postgres stores only `has_documents: "true"` (boolean flag)
- Full document metadata lives in Unity Catalog volume's `metadata.json`
- Reconstructing chips requires slow volume access

## Solution

Store document metadata (`filename`, `size`, `uploaded_at`) in `chat_threads.metadata` JSONB field. Return this data with the thread messages response so frontend can render chips instantly.

## Data Structure

**`chat_threads.metadata` JSONB:**
```json
{
  "has_documents": "true",
  "documents": [
    {"filename": "report.pdf", "size": 2048576, "uploaded_at": "2024-01-15T10:30:00Z"},
    {"filename": "notes.txt", "size": 1024, "uploaded_at": "2024-01-15T10:31:00Z"}
  ]
}
```

Threads without documents: `"documents": []`

## API Response

**`GET /api/threads/{thread_id}/messages`:**
```json
{
  "messages": [...],
  "thread_id": "uuid",
  "documents": [
    {"filename": "report.pdf", "size": 2048576, "uploaded_at": "2024-01-15T10:30:00Z"}
  ]
}
```

## Backend Changes

### `backend/database.py`

Add method to update thread document metadata:

```python
def update_thread_documents(self, thread_id: str, documents: List[Dict]) -> None:
    """
    Update thread metadata with document list for chip reconstruction.

    Args:
        thread_id: The thread UUID
        documents: List of {"filename": str, "size": int, "uploaded_at": str}
    """
    # Merge into existing metadata, set has_documents=true
```

### `backend/routers/chat.py`

In `send_with_documents` endpoint, after receiving files:

1. Build documents list with filename, size, uploaded_at
2. Call `chat_db.update_thread_documents(thread_id, documents)`

### `backend/routers/threads.py`

In `get_thread_messages` endpoint:

1. Fetch thread metadata from database
2. Extract `documents` array (default to `[]` if missing)
3. Include in response alongside messages

## Frontend Changes

### `lib/core/services/fastapi_service.dart`

Update `getThreadMessages()` to parse and return `documents` array from response.

### `lib/features/chat/presentation/chat_home_page.dart`

In `_loadThreadConversation()`:

1. Extract `documents` from the messages API response
2. Call `ref.read(documentsProvider.notifier).loadFromBackend(docs)`
3. Remove separate call to `getThreadDocuments()` (no longer needed)

## What Stays the Same

- `DocumentChip` widget - no changes needed
- `documentsProvider` and `loadFromBackend()` - already expects this format
- Document content loading for LLM (`load_documents_via_sql()`) - unchanged
- Volume `metadata.json` - continues to be written as source of truth

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Thread with documents | Return `documents` array with metadata |
| Thread without documents | Return `documents: []` |
| Old thread (pre-feature) | Return `documents: []` (no backfill) |

## Not In Scope

- Schema migration (using existing JSONB field)
- Backfilling old threads (they work via existing volume fallback)
- Changes to document content loading path
