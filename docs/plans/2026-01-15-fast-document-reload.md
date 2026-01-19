# Fast Document Reload Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace slow SDK-based document loading with fast SQL-based READ_FILES() and smart reload logic that only fetches documents when returning to old threads.

**Architecture:**
- Use PostgreSQL to track which thread is the user's most recent (by `updated_at`)
- Only reload documents from Unity Catalog volume when user returns to an OLD doc thread
- Use Databricks SQL `READ_FILES()` for fast document retrieval (~1-2s vs SDK timeout issues)
- Keep the inline document flow for new uploads unchanged (already fast)

**Tech Stack:**
- `databricks-sql-connector` for SQL warehouse access
- PostgreSQL for thread metadata (already configured)
- Unity Catalog volumes for document storage

---

## Task 1: Add SQL Warehouse Client to Document Service

**Files:**
- Modify: `deployment/document_service.py:1-50`

**Step 1: Add SQL connector imports and config**

Add these imports and config after line 14:

```python
from databricks import sql as databricks_sql

# SQL Warehouse configuration
SQL_WAREHOUSE_HOSTNAME = os.environ.get('HOSTNAME', '').replace('https://', '')
SQL_WAREHOUSE_HTTP_PATH = os.environ.get('HTTP_PATH', '')
```

**Step 2: Add SQL client property to DocumentService class**

Add after the `workspace_client` property (around line 69):

```python
@property
def sql_connection(self):
    """Get Databricks SQL connection for fast file reads"""
    return databricks_sql.connect(
        server_hostname=SQL_WAREHOUSE_HOSTNAME,
        http_path=SQL_WAREHOUSE_HTTP_PATH,
        access_token=DATABRICKS_TOKEN
    )
```

**Step 3: Verify imports work**

Run: `cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/deployment && python3 -c "from document_service import document_service; print('OK')"`

Expected: `OK`

**Step 4: Commit**

```bash
git add deployment/document_service.py
git commit -m "feat: add SQL warehouse client for fast document reads"
```

---

## Task 2: Add SQL-based Document Loading Method

**Files:**
- Modify: `deployment/document_service.py:273-300`

**Step 1: Add `load_documents_via_sql()` method**

Add this new method after `load_documents_for_model()`:

```python
def load_documents_via_sql(self, user_id: str, thread_id: str) -> List[Dict]:
    """
    Load documents using Databricks SQL READ_FILES() - much faster than SDK download.
    Returns documents formatted for LLM API.
    """
    import time
    start = time.time()
    thread_path = self.get_thread_documents_path(user_id, thread_id)
    logger.info(f"[DOC_SQL] Loading documents via SQL from {thread_path}")

    result = []

    try:
        with self.sql_connection as conn:
            with conn.cursor() as cursor:
                # Query to find all files in the thread directory (excluding metadata.json)
                # Using READ_FILES with binaryFile format returns base64-encoded content
                query = f"""
                    SELECT
                        path,
                        content
                    FROM READ_FILES(
                        '{thread_path}/*',
                        format => 'binaryFile'
                    )
                    WHERE path NOT LIKE '%metadata.json'
                """
                cursor.execute(query)
                rows = cursor.fetchall()

                for row in rows:
                    file_path = row[0]
                    base64_content = row[1]
                    filename = file_path.split('/')[-1]

                    if filename.lower().endswith('.pdf'):
                        result.append({
                            'type': 'document',
                            'source': {
                                'type': 'base64',
                                'media_type': 'application/pdf',
                                'data': base64_content
                            }
                        })
                    else:
                        # Decode base64 for text files
                        import base64
                        text_bytes = base64.b64decode(base64_content)
                        result.append({
                            'type': 'text',
                            'text': f"[Document: {filename}]\n\n{text_bytes.decode('utf-8')}"
                        })

                    logger.info(f"[DOC_SQL] Loaded {filename}")

        elapsed = time.time() - start
        logger.info(f"[DOC_SQL] Loaded {len(result)} documents in {elapsed:.2f}s")

    except Exception as e:
        elapsed = time.time() - start
        logger.error(f"[DOC_SQL] Error loading documents after {elapsed:.2f}s: {e}")
        # Fall back to empty - don't block the chat

    return result
```

**Step 2: Test SQL loading manually**

Run: `cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/deployment && python3 -c "
from document_service import document_service
# Use a known user_id and thread_id that has documents
docs = document_service.load_documents_via_sql('5584783103064141@7474645105283837', '3460f08a-287f-497b-ac34-752b744b7241')
print(f'Loaded {len(docs)} documents')
for d in docs:
    print(f'  Type: {d.get(\"type\")}, Size: {len(str(d))}')
"`

Expected: Documents load in ~1-2 seconds

**Step 3: Commit**

```bash
git add deployment/document_service.py
git commit -m "feat: add SQL-based document loading with READ_FILES()"
```

---

## Task 3: Add Smart Reload Logic to Database

**Files:**
- Modify: `deployment/database.py:333-356`

**Step 1: Add `get_user_most_recent_thread()` method**

Add after `thread_has_documents()`:

```python
def get_user_most_recent_thread(self, user_id: str) -> Optional[str]:
    """Get the most recently updated thread for a user (by updated_at timestamp)"""
    query = """
        SELECT thread_id
        FROM chat_threads
        WHERE user_id = %s
        ORDER BY updated_at DESC
        LIMIT 1
    """
    result = self.db.execute_query_one(query, (user_id,))
    return str(result['thread_id']) if result else None
```

**Step 2: Add `needs_document_reload()` method**

Add after `get_user_most_recent_thread()`:

```python
def needs_document_reload(self, user_id: str, thread_id: str) -> bool:
    """
    Check if documents need to be reloaded from volume.
    Returns True if:
    - Thread has documents AND
    - Thread is NOT the user's most recent thread (user is returning to old thread)
    """
    if not self.thread_has_documents(thread_id):
        return False

    most_recent = self.get_user_most_recent_thread(user_id)
    needs_reload = most_recent != thread_id
    logger.info(f"[DB] needs_document_reload: thread={thread_id}, most_recent={most_recent}, needs_reload={needs_reload}")
    return needs_reload
```

**Step 3: Test the logic**

Run: `cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/deployment && python3 -c "
from database import initialize_database
db = initialize_database()
user_id = '5584783103064141@7474645105283837'
most_recent = db.get_user_most_recent_thread(user_id)
print(f'Most recent thread for user: {most_recent}')
"`

Expected: Returns a valid thread_id

**Step 4: Commit**

```bash
git add deployment/database.py
git commit -m "feat: add smart document reload detection logic"
```

---

## Task 4: Update /send Endpoint with Smart Reload Logic

**Files:**
- Modify: `deployment/routers/chat.py:425-442`

**Step 1: Replace the document check block**

Replace lines 425-442:

```python
        # Check if thread has documents - route to Claude if so
        # Use fast DB metadata check instead of slow volume check
        has_documents = False
        if thread_id:
            logger.info(f"[CHAT] Checking if thread {thread_id} has documents (DB metadata check)")
            has_documents = chat_db.thread_has_documents(thread_id)
            logger.info(f"[CHAT] thread_has_documents check result={has_documents}")

        if has_documents:
            # Route to Claude with documents
            logger.info(f"Thread {thread_id} has documents, routing to Claude")
            return await _handle_document_chat(
                message_text=message_text,
                thread_id=thread_id,
                user_id=user_id,
                conversation_history=conversation_history,
                use_streaming=use_streaming
            )
```

With:

```python
        # Check if thread has documents and whether we need to reload them
        has_documents = False
        needs_reload = False
        if thread_id:
            logger.info(f"[CHAT] Checking if thread {thread_id} has documents (DB metadata check)")
            has_documents = chat_db.thread_has_documents(thread_id)
            if has_documents:
                needs_reload = chat_db.needs_document_reload(user_id, thread_id)
            logger.info(f"[CHAT] has_documents={has_documents}, needs_reload={needs_reload}")

        if has_documents:
            # Route to Claude with documents
            logger.info(f"[CHAT] Thread {thread_id} has documents, routing to document chat")
            return await _handle_document_chat(
                message_text=message_text,
                thread_id=thread_id,
                user_id=user_id,
                conversation_history=conversation_history,
                use_streaming=use_streaming,
                reload_documents=needs_reload  # New parameter
            )
```

**Step 2: Commit**

```bash
git add deployment/routers/chat.py
git commit -m "feat: add smart reload detection to /send endpoint"
```

---

## Task 5: Update _handle_document_chat to Accept reload_documents

**Files:**
- Modify: `deployment/routers/chat.py:254-316`

**Step 1: Update function signature and logic**

Replace the `_handle_document_chat` function:

```python
async def _handle_document_chat(
    message_text: str,
    thread_id: str,
    user_id: str,
    conversation_history: List[dict],
    use_streaming: bool,
    reload_documents: bool = False  # New parameter
):
    """Handle chat with document context via Claude"""
    # Save user message
    user_message_id = chat_db.save_message(
        thread_id=thread_id,
        user_id=user_id,
        message_role="user",
        message_content=message_text,
        agent_endpoint=DATABRICKS_DOCUMENT_MODEL
    )

    if use_streaming:
        def generate_stream():
            try:
                # Send metadata first
                yield f"data: {json.dumps({'metadata': {'thread_id': thread_id, 'user_message_id': user_message_id, 'user_id': user_id, 'agent_endpoint': DATABRICKS_DOCUMENT_MODEL}})}\n\n"

                full_response_parts = []

                # Only reload documents if returning to old thread
                if reload_documents:
                    logger.info(f"[DOC_CHAT] Reloading documents for old thread {thread_id}")
                    doc_contents = document_service.load_documents_via_sql(user_id, thread_id)

                    # Stream from model with reloaded documents
                    for content in _stream_with_docs(
                        message=message_text,
                        doc_contents=doc_contents,
                        conversation_history=conversation_history
                    ):
                        full_response_parts.append(content)
                        yield f"data: {json.dumps({'content': content})}\n\n"
                else:
                    # Documents already in conversation context, just continue
                    logger.info(f"[DOC_CHAT] Continuing doc chat (docs in context)")
                    for content in _stream_without_reload(
                        message=message_text,
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
                        agent_endpoint=DATABRICKS_DOCUMENT_MODEL
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
        # Non-streaming mode (simplified)
        try:
            if reload_documents:
                doc_contents = document_service.load_documents_via_sql(user_id, thread_id)
                full_response_parts = list(_stream_with_docs(message_text, doc_contents, conversation_history))
            else:
                full_response_parts = list(_stream_without_reload(message_text, conversation_history))

            full_response = ''.join(full_response_parts)

            assistant_message_id = chat_db.save_message(
                thread_id=thread_id,
                user_id=user_id,
                message_role="assistant",
                message_content=full_response,
                agent_endpoint=DATABRICKS_DOCUMENT_MODEL
            )

            return {
                "response": full_response,
                "citations": [],
                "backend": "claude",
                "thread_id": thread_id,
                "user_message_id": user_message_id,
                "assistant_message_id": assistant_message_id,
                "agent_endpoint": DATABRICKS_DOCUMENT_MODEL,
                "status": "success"
            }
        except Exception as e:
            return {
                "response": f"Error: {str(e)}",
                "backend": "claude",
                "status": "error"
            }
```

**Step 2: Commit**

```bash
git add deployment/routers/chat.py
git commit -m "feat: update _handle_document_chat with conditional reload"
```

---

## Task 6: Add Helper Streaming Functions

**Files:**
- Modify: `deployment/routers/chat.py:168-252`

**Step 1: Replace `stream_model_with_documents` with two helpers**

Replace the entire `stream_model_with_documents` function with these two helpers:

```python
def _stream_with_docs(
    message: str,
    doc_contents: List[dict],
    conversation_history: List[dict]
):
    """Stream response with documents prepended (for reload case)"""
    messages = []

    # Add document context as first user message
    if doc_contents:
        doc_message_content = doc_contents + [{
            'type': 'text',
            'text': 'I have uploaded the above documents. Please use them to answer my questions.'
        }]
        messages.append({'role': 'user', 'content': doc_message_content})
        messages.append({
            'role': 'assistant',
            'content': 'I have received and reviewed the documents. What would you like to know?'
        })

    # Add conversation history
    for msg in conversation_history:
        messages.append({'role': msg.get('role', 'user'), 'content': msg.get('content', '')})

    # Add current message
    messages.append({'role': 'user', 'content': message})

    logger.info(f"[DOC_STREAM] Calling model with {len(messages)} messages, {len(doc_contents)} docs")

    client = document_service.model_client
    response = client.chat.completions.create(
        model=DATABRICKS_DOCUMENT_MODEL,
        messages=messages,
        stream=True
    )

    for chunk in response:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content


def _stream_without_reload(
    message: str,
    conversation_history: List[dict]
):
    """Stream response for continuing doc chat (docs already in conversation context)"""
    messages = []

    # Add conversation history (which already contains the document context)
    for msg in conversation_history:
        messages.append({'role': msg.get('role', 'user'), 'content': msg.get('content', '')})

    # Add current message
    messages.append({'role': 'user', 'content': message})

    logger.info(f"[DOC_STREAM] Continuing doc chat with {len(messages)} messages (no reload)")

    client = document_service.model_client
    response = client.chat.completions.create(
        model=DATABRICKS_DOCUMENT_MODEL,
        messages=messages,
        stream=True
    )

    for chunk in response:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content
```

**Step 2: Commit**

```bash
git add deployment/routers/chat.py
git commit -m "refactor: split document streaming into reload and no-reload paths"
```

---

## Task 7: Clean Up Old SDK-based Loading in document_service.py

**Files:**
- Modify: `deployment/document_service.py`

**Step 1: Remove or deprecate `load_documents_for_model()`**

The old `load_documents_for_model()` method uses the slow SDK. We can either:
- Delete it entirely
- Or mark it as deprecated and keep for fallback

For safety, mark as deprecated by adding a docstring warning:

```python
def load_documents_for_model(self, user_id: str, thread_id: str) -> List[Dict]:
    """
    DEPRECATED: Use load_documents_via_sql() instead for faster loading.
    This method uses the slow SDK download which can timeout.
    Kept for backward compatibility only.
    """
    logger.warning("[DOC_SVC] load_documents_for_model is deprecated, use load_documents_via_sql")
    # ... rest of existing implementation
```

**Step 2: Remove slow `_read_file_content()` calls from `list_documents()` and `save_document()`**

In `save_document()`, the `list_documents()` call triggers a slow metadata read. Replace line 115:

```python
# Old: existing_docs = self.list_documents(user_id, thread_id)
# New: Skip count check during background save (files were already validated)
# The MAX_FILES_PER_THREAD limit is enforced at upload time in the endpoint
```

Actually, for the background save case, we should pass a flag. Update `save_document()` signature:

```python
def save_document(
    self,
    user_id: str,
    thread_id: str,
    filename: str,
    content: bytes,
    skip_count_check: bool = False  # New parameter for background saves
) -> Dict:
    """Save a document to the volume (Unity Catalog or local)"""
    if not skip_count_check:
        # Only check count if not a background save
        existing_docs = self.list_documents(user_id, thread_id)
        if len(existing_docs) >= MAX_FILES_PER_THREAD:
            raise ValueError(f"Maximum {MAX_FILES_PER_THREAD} documents per thread exceeded")
    # ... rest unchanged
```

And update `save_documents_background()` to pass `skip_count_check=True`:

```python
async def save_documents_background(
    self,
    user_id: str,
    thread_id: str,
    files: List[Tuple[str, bytes]]
):
    """Save documents to volume in background (fire-and-forget)"""
    loop = asyncio.get_event_loop()
    for filename, content in files:
        try:
            await loop.run_in_executor(
                _executor,
                lambda: self.save_document(user_id, thread_id, filename, content, skip_count_check=True)
            )
            logger.info(f"[BACKGROUND] Saved document to volume: {filename}")
        except Exception as e:
            logger.error(f"[BACKGROUND] Failed to save {filename}: {e}")
```

**Step 3: Commit**

```bash
git add deployment/document_service.py
git commit -m "fix: skip slow volume read during background document save"
```

---

## Task 8: Test Upload Flow (New Doc Chat)

**Files:**
- None (testing only)

**Step 1: Start the backend server**

Run: `cd /Users/sathish.gangichetty/AndroidStudioProjects/chat-app-bespoke/brickchat/deployment && uv run python app.py`

**Step 2: Test upload via curl**

Run (in another terminal):
```bash
curl -X POST http://localhost:8000/api/chat/send-with-documents \
  -F "message=What is this document about?" \
  -F "files=@/path/to/test.pdf" \
  -H "X-Forwarded-Email: test@example.com"
```

Expected:
- Fast response (no blocking)
- Logs show `[SEND_WITH_DOCS]` flow, NOT `[DOC_SVC] Downloading file...`

**Step 3: Verify no blocking reads in logs**

Check logs for absence of:
- `[DOC_SVC] _read_file_content`
- `[DOC_SVC] Downloading file...`

---

## Task 9: Test Return to Old Doc Thread Flow

**Files:**
- None (testing only)

**Step 1: Get an existing doc thread ID from the database**

Run: `psql` and query:
```sql
SELECT thread_id FROM chat_threads
WHERE metadata->>'has_documents' = 'true'
ORDER BY updated_at DESC LIMIT 1;
```

**Step 2: Send a message to that thread via /send**

```bash
curl -X POST http://localhost:8000/api/chat/send \
  -H "Content-Type: application/json" \
  -H "X-Forwarded-Email: test@example.com" \
  -d '{"message": "Tell me more about the document", "thread_id": "<thread_id_from_step1>"}'
```

Expected:
- Logs show `[DOC_SQL] Loading documents via SQL`
- Load completes in ~1-2 seconds
- Response streams successfully

---

## Task 10: Test Regular Chat (No Docs) Still Works

**Files:**
- None (testing only)

**Step 1: Send a regular message without thread_id**

```bash
curl -X POST http://localhost:8000/api/chat/send \
  -H "Content-Type: application/json" \
  -H "X-Forwarded-Email: test@example.com" \
  -d '{"message": "Hello, what can you help me with?"}'
```

Expected:
- Normal response from Databricks model
- No document-related logs
- Fast response

**Step 2: Commit final changes**

```bash
git add -A
git commit -m "test: verify all chat flows work correctly"
```

---

## Summary of Changes

| File | Changes |
|------|---------|
| `deployment/document_service.py` | Add SQL warehouse client, `load_documents_via_sql()`, skip count check in background save |
| `deployment/database.py` | Add `get_user_most_recent_thread()`, `needs_document_reload()` |
| `deployment/routers/chat.py` | Update `/send` with smart reload logic, split streaming helpers |

## Flows After Implementation

| Scenario | Flow | Speed |
|----------|------|-------|
| New upload | `/send-with-documents` → inline docs → background save | Fast (no blocking) |
| Continue doc chat | `/send` → `has_documents=true`, `needs_reload=false` → no doc fetch | Fast |
| Return to old doc thread | `/send` → `has_documents=true`, `needs_reload=true` → SQL READ_FILES | ~1-2s |
| Regular chat | `/send` → `has_documents=false` → normal Databricks | Fast |
