from fastapi import APIRouter, HTTPException, Depends, Query
from fastapi.responses import StreamingResponse
from openai import OpenAI
import os
from dotenv import load_dotenv
import json
import re
from typing import List
from database import initialize_database
from auth import get_current_user, UserContext
from document_service import document_service, DATABRICKS_DOCUMENT_MODEL
import logging

load_dotenv()

router = APIRouter(prefix="/api/chat", tags=["chat"])

# =============================================================================
# Pre-compiled regex patterns (compiled once at module load, not per-request)
# =============================================================================

# Patterns to detect Knowledge Assistant reasoning phrases
_REASONING_PATTERNS = [
    r'Establishing a working model',
    r'Decomposing the question',
    r'targeted sub-queries',
    r'Consolidating results',
    r'across sub-queries',
    r'Searching [a-zA-Z0-9\-]+\.\.\.',
    r'Staging key excerpts',
    r'for inspection',
    r'The user asked:',
    r'The provided source is',
    r'I will extract',
    r'salient points',
    r'No external search needed',
    r'For retrieval query',
    r'produce a clear',
    r'unambiguous query',
    r'unique aspects',
    r'I have several documents',
    r'Let me pull together',
    r'key highlights',
]
_REASONING_REGEX = re.compile('|'.join(_REASONING_PATTERNS), re.IGNORECASE)

# Pattern to detect actual content start
_CONTENT_START_PATTERNS = [
    r'^Key\s+(Q\d+|[\w\s]+)\s+results?:',
    r'^\s*[-•*]\s+',
    r'^\s*\d+\.\s+',
    r'^Here are',
    r'^Based on',
    r'^The (key|main|primary)',
    r'^\*\*',
    r'^#{1,6}\s+',
]
_CONTENT_START_REGEX = re.compile('|'.join(_CONTENT_START_PATTERNS), re.MULTILINE | re.IGNORECASE)

# Patterns for inline reasoning detection in streaming
_INLINE_REASONING_PATTERNS = [
    r'Mapping query intent',
    r'Filtering to the highest-value',
    r'Searching [a-zA-Z0-9\-]+\.\.\.',
    r'Structuring selected content',
    r'answer synthesis',
    r'Establishing a working model',
    r'Decomposing the question',
    r'targeted sub-queries',
    r'Consolidating results',
    r'Staging key excerpts',
    r'for inspection',
    r'salient points',
    r'For retrieval query',
    r'Let me pull together',
]
_INLINE_REASONING_REGEX = re.compile('|'.join(_INLINE_REASONING_PATTERNS), re.IGNORECASE)

# Patterns that indicate actual content has started
_REAL_CONTENT_PATTERNS = [
    r'^Great question',
    r'^Here are',
    r'^Based on',
    r'^The (key|main|primary|top)',
    r'^\*\*[A-Z]',  # Bold header starting with capital
    r'^I\'m happy to',
    r'^Thank you for',
    r'^Let me share',
    r'^Here\'s what',
]
_REAL_CONTENT_REGEX = re.compile('|'.join(_REAL_CONTENT_PATTERNS), re.IGNORECASE)

# Configuration
MAX_CONVERSATION_MESSAGES = int(os.environ.get('MAX_CONVERSATION_MESSAGES', '20'))

# Initialize database for message tracking
chat_db = initialize_database()
logger = logging.getLogger(__name__)

# Databricks configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL')


def get_databricks_client() -> OpenAI:
    """
    Get an OpenAI client configured for Databricks.

    Always uses the app's DATABRICKS_TOKEN for all API calls.
    User context (from X-Forwarded headers) is only used for identification,
    not for authentication to Databricks services.
    """
    return OpenAI(
        api_key=DATABRICKS_TOKEN,
        base_url=DATABRICKS_BASE_URL
    )


def _wrap_reasoning_in_response(full_response: str) -> str:
    """
    Process the full response to wrap reasoning content in <think> tags.
    This ensures stored messages have proper structure for the frontend.
    Uses pre-compiled module-level regex patterns for performance.
    """
    # Split into lines/paragraphs and find where reasoning ends
    lines = full_response.split('\n')
    reasoning_lines = []
    content_lines = []
    in_reasoning = True

    for line in lines:
        if in_reasoning:
            # Check if this line starts actual content (using pre-compiled patterns)
            if _CONTENT_START_REGEX.search(line) and not _REASONING_REGEX.search(line):
                in_reasoning = False
                content_lines.append(line)
            else:
                reasoning_lines.append(line)
        else:
            content_lines.append(line)

    # If we found reasoning content, wrap it
    if reasoning_lines:
        reasoning_text = '\n'.join(reasoning_lines).strip()
        content_text = '\n'.join(content_lines).strip()

        if reasoning_text and content_text:
            return f"<think>\n{reasoning_text}\n</think>\n\n{content_text}"
        elif reasoning_text:
            # Only reasoning, no content (shouldn't happen normally)
            return f"<think>\n{reasoning_text}\n</think>"

    # No reasoning detected, return as-is
    return full_response


@router.get("/config")
async def get_config():
    """Get current chat configuration including agent endpoint"""
    return {
        "agent_endpoint": DATABRICKS_MODEL,
        "status": "success"
    }


# =============================================================================
# Document Chat Functions (Claude integration)
# =============================================================================

def stream_claude_with_documents(
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
        model=DATABRICKS_DOCUMENT_MODEL,
        messages=messages,
        stream=True
    )

    for chunk in response:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content


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
        agent_endpoint=DATABRICKS_DOCUMENT_MODEL
    )

    if use_streaming:
        def generate_stream():
            try:
                # Send metadata first
                yield f"data: {json.dumps({'metadata': {'thread_id': thread_id, 'user_message_id': user_message_id, 'user_id': user_id, 'agent_endpoint': DATABRICKS_DOCUMENT_MODEL}})}\n\n"

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


@router.get("/threads")
async def get_user_threads(user: UserContext = Depends(get_current_user)):
    """Get all chat threads for the authenticated user with their last message"""
    try:
        threads = chat_db.get_user_threads_with_last_message(user.user_id)
        return {"threads": threads, "user_id": user.user_id}
    except Exception as e:
        logger.error(f"Error fetching threads for {user.user_id}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch threads: {str(e)}")


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


@router.post("/send")
async def send_message(message: dict, user: UserContext = Depends(get_current_user)):
    """Send a chat message to Databricks endpoint with conversation history and track in database"""
    try:
        # Extract the message text from the request
        message_text = message.get("message", "").strip()
        if not message_text:
            raise HTTPException(status_code=400, detail="Message text is required")

        # Extract conversation history (optional) and apply limits to prevent token explosion
        conversation_history = message.get("conversation_history", [])

        # Limit conversation history to prevent excessive token usage
        if len(conversation_history) > MAX_CONVERSATION_MESSAGES:
            # Preserve system prompt if present, then take most recent messages
            if conversation_history and conversation_history[0].get('role') == 'system':
                conversation_history = [conversation_history[0]] + conversation_history[-(MAX_CONVERSATION_MESSAGES - 1):]
            else:
                conversation_history = conversation_history[-MAX_CONVERSATION_MESSAGES:]
            logger.info(f"Truncated conversation history to {len(conversation_history)} messages (max: {MAX_CONVERSATION_MESSAGES})")

        # Extract stream parameter (defaults to True for backward compatibility)
        use_streaming = message.get("stream", True)

        # Extract or create thread ID - user_id comes from auth context
        thread_id = message.get("thread_id")
        user_id = user.user_id

        # Create new thread if not provided
        if not thread_id:
            thread_id = chat_db.create_thread(user_id=user_id)
            logger.info(f"Created new thread: {thread_id}")

        # Check if thread has documents - route to Claude if so
        has_documents = False
        if thread_id:
            has_documents = document_service.thread_has_documents(user_id, thread_id)

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

        # Save user message to database
        user_message_id = chat_db.save_message(
            thread_id=thread_id,
            user_id=user_id,
            message_role="user",
            message_content=message_text,
            agent_endpoint=None  # User messages don't have agent endpoint
        )

        # Check if we have the app's token configured
        if not DATABRICKS_TOKEN:
            raise HTTPException(
                status_code=503,
                detail="DATABRICKS_TOKEN not configured. Please set DATABRICKS_TOKEN environment variable."
            )

        # Get client using app's service principal token
        client = get_databricks_client()

        # Prepare the input array for Databricks endpoint
        input_array = []

        # Add conversation history if provided
        if conversation_history:
            for msg in conversation_history:
                input_array.append({
                    "role": msg.get("role", "user"),
                    "content": msg.get("content", "")
                })

        # Add the current message
        input_array.append({
            "role": "user",
            "content": message_text
        })

        # Send message to Databricks using the working pattern
        try:
            response = client.responses.create(
                model=DATABRICKS_MODEL,
                input=input_array,
                stream=use_streaming
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Databricks API error: {str(e)}")

        if use_streaming:
            # Create streaming response that captures both text and annotations
            def generate_stream():
                try:
                    # Send metadata first (thread_id, user_message_id, agent_endpoint)
                    yield f"data: {json.dumps({'metadata': {'thread_id': thread_id, 'user_message_id': user_message_id, 'user_id': user_id, 'agent_endpoint': DATABRICKS_MODEL}})}\n\n"

                    # Use list accumulation for better performance (avoid string += overhead)
                    full_response_parts = []
                    reasoning_parts = []
                    output_parts = []
                    text_buffer_parts = []
                    inline_reasoning_parts = []

                    # Citations with deduplication during collection
                    citations = []
                    seen_citation_urls = set()
                    current_content_index = 0

                    # Buffer state for detecting inline reasoning in text stream
                    in_inline_reasoning = True  # Start assuming we're in reasoning until we see real content

                    # Use pre-compiled module-level regex patterns (_INLINE_REASONING_REGEX, _REAL_CONTENT_REGEX)

                    for chunk in response:
                        event_type = type(chunk).__name__

                        # Handle reasoning events (ResponseReasoningSummaryTextDeltaEvent)
                        if 'Reasoning' in event_type and hasattr(chunk, 'delta') and chunk.delta:
                            reasoning_parts.append(chunk.delta)

                        # Handle text output events (ResponseTextDeltaEvent)
                        elif event_type == 'ResponseTextDeltaEvent' and hasattr(chunk, 'delta') and chunk.delta:
                            delta = chunk.delta

                            # Check if this text contains </think> tag - everything before is reasoning
                            if '</think>' in delta:
                                parts = delta.split('</think>', 1)
                                inline_reasoning_parts.append(parts[0])
                                in_inline_reasoning = False
                                # The part after </think> is real content
                                if len(parts) > 1:
                                    remaining = parts[1].lstrip('\n')
                                    if remaining:
                                        output_parts.append(remaining)
                                        full_response_parts.append(remaining)
                                        yield f"data: {json.dumps({'content': remaining})}\n\n"
                                continue

                            # If we're still in potential reasoning phase, buffer the text
                            if in_inline_reasoning:
                                text_buffer_parts.append(delta)
                                text_buffer = ''.join(text_buffer_parts)

                                # Check if buffer now contains real content start (using pre-compiled pattern)
                                if _REAL_CONTENT_REGEX.search(text_buffer):
                                    in_inline_reasoning = False
                                    # Everything in buffer is actual content
                                    output_parts.append(text_buffer)
                                    full_response_parts.append(text_buffer)
                                    yield f"data: {json.dumps({'content': text_buffer})}\n\n"
                                    text_buffer_parts.clear()
                                # Check if buffer looks like inline reasoning (using pre-compiled pattern)
                                elif _INLINE_REASONING_REGEX.search(text_buffer) or text_buffer.startswith('['):
                                    # Keep buffering as reasoning
                                    inline_reasoning_parts.append(delta)
                                # Buffer is getting long without clear signal - flush as content
                                elif len(text_buffer) > 500:
                                    in_inline_reasoning = False
                                    output_parts.append(text_buffer)
                                    full_response_parts.append(text_buffer)
                                    yield f"data: {json.dumps({'content': text_buffer})}\n\n"
                                    text_buffer_parts.clear()
                            else:
                                # We're past reasoning, stream content normally
                                output_parts.append(delta)
                                full_response_parts.append(delta)
                                yield f"data: {json.dumps({'content': delta})}\n\n"

                            # Track content index (increments on major boundaries)
                            if hasattr(chunk, 'content_index'):
                                current_content_index = chunk.content_index

                        # Handle annotation events (ResponseOutputTextAnnotationAddedEvent)
                        # Deduplicate citations during collection (not after)
                        elif 'Annotation' in event_type:
                            ann = getattr(chunk, 'annotation', None)
                            content_idx = getattr(chunk, 'content_index', current_content_index)

                            if ann and isinstance(ann, dict):
                                url = ann.get('url')
                                # Deduplicate during collection using seen_citation_urls set
                                if url and url not in seen_citation_urls:
                                    seen_citation_urls.add(url)
                                    citations.append({
                                        'id': str(len(citations) + 1),
                                        'content_index': content_idx,
                                        'title': ann.get('title'),
                                        'url': url,
                                    })
                                    logger.info(f"[CITATION] Block {content_idx}: {ann.get('title')}")

                    # If there's remaining buffer that never got flushed, treat it as content
                    text_buffer = ''.join(text_buffer_parts)
                    if text_buffer and in_inline_reasoning:
                        # This was never clearly reasoning, so output it
                        output_parts.append(text_buffer)
                        full_response_parts.append(text_buffer)
                        yield f"data: {json.dumps({'content': text_buffer})}\n\n"

                    # Combine all reasoning content (from events + inline detected)
                    reasoning_content = ''.join(reasoning_parts)
                    inline_reasoning_collected = ''.join(inline_reasoning_parts)
                    all_reasoning = reasoning_content + inline_reasoning_collected

                    # After streaming completes, send reasoning wrapped in <think> tags
                    if all_reasoning.strip():
                        # Clean up any stray </think> or <think> tags from the reasoning
                        clean_reasoning = re.sub(r'</?think>', '', all_reasoning).strip()
                        if clean_reasoning:
                            wrapped_reasoning = f"<think>\n{clean_reasoning}\n</think>\n\n"
                            yield f"data: {json.dumps({'reasoning': wrapped_reasoning})}\n\n"

                    # Send citations if any were collected (already deduplicated during collection)
                    if citations:
                        logger.info(f"[CITATIONS] Sending {len(citations)} unique citations")
                        yield f"data: {json.dumps({'citations': citations})}\n\n"

                    # Save assistant message to database
                    output_content = ''.join(output_parts)
                    if output_content:
                        try:
                            # Combine all reasoning (events + inline) and output for storage
                            content_to_save = output_content
                            if all_reasoning.strip():
                                clean_reasoning = re.sub(r'</?think>', '', all_reasoning).strip()
                                if clean_reasoning:
                                    content_to_save = f"<think>\n{clean_reasoning}\n</think>\n\n{output_content}"

                            assistant_message_id = chat_db.save_message(
                                thread_id=thread_id,
                                user_id=user_id,
                                message_role="assistant",
                                message_content=content_to_save,
                                agent_endpoint=DATABRICKS_MODEL
                            )
                            yield f"data: {json.dumps({'assistant_message_id': assistant_message_id})}\n\n"
                        except Exception as e:
                            logger.error(f"Failed to save assistant message: {e}")

                    # Send end signal
                    yield f"data: {json.dumps({'done': True})}\n\n"

                except Exception as e:
                    logger.error(f"Streaming error: {e}")
                    yield f"data: {json.dumps({'error': str(e)})}\n\n"

            return StreamingResponse(
                generate_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "*",
                }
            )
        else:
            # Non-streaming response - extract content and citations from response object
            try:
                full_content = ""
                citations = []

                if hasattr(response, 'output') and response.output:
                    for output_message in response.output:
                        if hasattr(output_message, 'content') and output_message.content:
                            for idx, content_item in enumerate(output_message.content):
                                if hasattr(content_item, 'text') and content_item.text:
                                    full_content += content_item.text

                                # Extract annotations (citations) from content item
                                if hasattr(content_item, 'annotations') and content_item.annotations:
                                    for ann in content_item.annotations:
                                        citation = {
                                            'content_index': idx,
                                            'title': getattr(ann, 'title', None),
                                            'url': getattr(ann, 'url', None),
                                            'type': getattr(ann, 'type', 'url_citation')
                                        }
                                        citations.append(citation)

                # Deduplicate citations by URL
                seen_urls = set()
                unique_citations = []
                for c in citations:
                    if c['url'] and c['url'] not in seen_urls:
                        seen_urls.add(c['url'])
                        unique_citations.append({
                            'id': str(len(unique_citations) + 1),
                            'title': c['title'],
                            'url': c['url'],
                            'content_index': c['content_index']
                        })

                # Save assistant message to database
                assistant_message_id = None
                if full_content:
                    assistant_message_id = chat_db.save_message(
                        thread_id=thread_id,
                        user_id=user_id,
                        message_role="assistant",
                        message_content=full_content,
                        agent_endpoint=DATABRICKS_MODEL
                    )

                return {
                    "response": full_content,
                    "citations": unique_citations,
                    "backend": "databricks",
                    "thread_id": thread_id,
                    "user_message_id": user_message_id,
                    "assistant_message_id": assistant_message_id,
                    "agent_endpoint": DATABRICKS_MODEL,
                    "status": "success"
                }
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Error processing response: {str(e)}")

    except Exception as e:
        return {
            "response": f"Error: {str(e)}",
            "backend": "databricks",
            "status": "error"
        }
