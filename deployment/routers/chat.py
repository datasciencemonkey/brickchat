from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from openai import OpenAI
import os
from dotenv import load_dotenv
import json
import re
from database import initialize_database
import logging

load_dotenv()

router = APIRouter(prefix="/api/chat", tags=["chat"])

# Initialize database for message tracking
chat_db = initialize_database()
logger = logging.getLogger(__name__)

# Databricks configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL')

# Initialize Databricks client
client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
)


def _wrap_reasoning_in_response(full_response: str) -> str:
    """
    Process the full response to wrap reasoning content in <think> tags.
    This ensures stored messages have proper structure for the frontend.
    """
    # Patterns to detect Knowledge Assistant reasoning phrases
    reasoning_patterns = [
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
    reasoning_regex = re.compile('|'.join(reasoning_patterns), re.IGNORECASE)

    # Pattern to detect actual content start
    content_start_patterns = [
        r'^Key\s+(Q\d+|[\w\s]+)\s+results?:',
        r'^\s*[-•*]\s+',
        r'^\s*\d+\.\s+',
        r'^Here are',
        r'^Based on',
        r'^The (key|main|primary)',
        r'^\*\*',
        r'^#{1,6}\s+',
    ]
    content_start_regex = re.compile('|'.join(content_start_patterns), re.MULTILINE | re.IGNORECASE)

    # Split into lines/paragraphs and find where reasoning ends
    lines = full_response.split('\n')
    reasoning_lines = []
    content_lines = []
    in_reasoning = True

    for line in lines:
        if in_reasoning:
            # Check if this line starts actual content
            if content_start_regex.search(line) and not reasoning_regex.search(line):
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


@router.get("/threads/{user_id}")
async def get_user_threads(user_id: str):
    """Get all chat threads for a user with their last message"""
    try:
        threads = chat_db.get_user_threads_with_last_message(user_id)
        return {"threads": threads}
    except Exception as e:
        logger.error(f"Error fetching threads: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch threads: {str(e)}")


@router.get("/threads/{thread_id}/messages")
async def get_thread_messages(thread_id: str):
    """Get all messages for a specific thread"""
    try:
        messages = chat_db.get_thread_messages(thread_id)
        return {"messages": messages}
    except Exception as e:
        logger.error(f"Error fetching thread messages: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch messages: {str(e)}")


@router.post("/send")
async def send_message(message: dict):
    """Send a chat message to Databricks endpoint with conversation history and track in database"""
    try:
        # Extract the message text from the request
        message_text = message.get("message", "").strip()
        if not message_text:
            raise HTTPException(status_code=400, detail="Message text is required")

        # Extract conversation history (optional)
        conversation_history = message.get("conversation_history", [])

        # Extract stream parameter (defaults to True for backward compatibility)
        use_streaming = message.get("stream", True)

        # Extract or create thread ID
        thread_id = message.get("thread_id")
        user_id = message.get("user_id", "dev_user")

        # Create new thread if not provided
        if not thread_id:
            thread_id = chat_db.create_thread(user_id=user_id)
            logger.info(f"Created new thread: {thread_id}")

        # Save user message to database
        user_message_id = chat_db.save_message(
            thread_id=thread_id,
            user_id=user_id,
            message_role="user",
            message_content=message_text,
            agent_endpoint=None  # User messages don't have agent endpoint
        )

        # Check if Databricks client is configured
        if not DATABRICKS_TOKEN:
            raise HTTPException(
                status_code=503,
                detail="Databricks token not configured. Please set DATABRICKS_TOKEN environment variable."
            )

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

                    # Collect content and citations
                    full_response = ""
                    reasoning_content = ""
                    output_content = ""
                    citations = []  # List of {content_index, title, url}
                    current_content_index = 0

                    # Buffer for detecting inline reasoning in text stream
                    text_buffer = ""
                    in_inline_reasoning = True  # Start assuming we're in reasoning until we see real content
                    inline_reasoning_collected = ""

                    # Patterns that indicate inline reasoning (model "thinking out loud")
                    inline_reasoning_patterns = [
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
                    inline_reasoning_regex = re.compile('|'.join(inline_reasoning_patterns), re.IGNORECASE)

                    # Patterns that indicate actual content has started
                    real_content_patterns = [
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
                    real_content_regex = re.compile('|'.join(real_content_patterns), re.IGNORECASE)

                    for chunk in response:
                        event_type = type(chunk).__name__

                        # Handle reasoning events (ResponseReasoningSummaryTextDeltaEvent)
                        if 'Reasoning' in event_type and hasattr(chunk, 'delta') and chunk.delta:
                            reasoning_content += chunk.delta

                        # Handle text output events (ResponseTextDeltaEvent)
                        elif event_type == 'ResponseTextDeltaEvent' and hasattr(chunk, 'delta') and chunk.delta:
                            delta = chunk.delta

                            # Check if this text contains </think> tag - everything before is reasoning
                            if '</think>' in delta:
                                parts = delta.split('</think>', 1)
                                inline_reasoning_collected += parts[0]
                                in_inline_reasoning = False
                                # The part after </think> is real content
                                if len(parts) > 1:
                                    remaining = parts[1].lstrip('\n')
                                    if remaining:
                                        output_content += remaining
                                        full_response += remaining
                                        yield f"data: {json.dumps({'content': remaining})}\n\n"
                                continue

                            # If we're still in potential reasoning phase, buffer the text
                            if in_inline_reasoning:
                                text_buffer += delta

                                # Check if buffer now contains real content start
                                if real_content_regex.search(text_buffer):
                                    in_inline_reasoning = False
                                    # Everything in buffer is actual content
                                    output_content += text_buffer
                                    full_response += text_buffer
                                    yield f"data: {json.dumps({'content': text_buffer})}\n\n"
                                    text_buffer = ""
                                # Check if buffer looks like inline reasoning
                                elif inline_reasoning_regex.search(text_buffer) or text_buffer.startswith('['):
                                    # Keep buffering as reasoning
                                    inline_reasoning_collected += delta
                                # Buffer is getting long without clear signal - flush as content
                                elif len(text_buffer) > 500:
                                    in_inline_reasoning = False
                                    output_content += text_buffer
                                    full_response += text_buffer
                                    yield f"data: {json.dumps({'content': text_buffer})}\n\n"
                                    text_buffer = ""
                            else:
                                # We're past reasoning, stream content normally
                                output_content += delta
                                full_response += delta
                                yield f"data: {json.dumps({'content': delta})}\n\n"

                            # Track content index (increments on major boundaries)
                            if hasattr(chunk, 'content_index'):
                                current_content_index = chunk.content_index

                        # Handle annotation events (ResponseOutputTextAnnotationAddedEvent)
                        # Note: In streaming mode, annotation is a dict, not an object
                        elif 'Annotation' in event_type:
                            ann = getattr(chunk, 'annotation', None)
                            content_idx = getattr(chunk, 'content_index', current_content_index)

                            if ann and isinstance(ann, dict):
                                citation = {
                                    'content_index': content_idx,
                                    'title': ann.get('title'),
                                    'url': ann.get('url'),
                                    'type': ann.get('type', 'url_citation')
                                }
                                citations.append(citation)
                                logger.info(f"[CITATION] Block {content_idx}: {citation['title']}")

                    # If there's remaining buffer that never got flushed, treat it as content
                    if text_buffer and in_inline_reasoning:
                        # This was never clearly reasoning, so output it
                        output_content += text_buffer
                        full_response += text_buffer
                        yield f"data: {json.dumps({'content': text_buffer})}\n\n"

                    # Combine all reasoning content (from events + inline detected)
                    all_reasoning = reasoning_content + inline_reasoning_collected

                    # After streaming completes, send reasoning wrapped in <think> tags
                    if all_reasoning.strip():
                        # Clean up any stray </think> or <think> tags from the reasoning
                        clean_reasoning = re.sub(r'</?think>', '', all_reasoning).strip()
                        if clean_reasoning:
                            wrapped_reasoning = f"<think>\n{clean_reasoning}\n</think>\n\n"
                            yield f"data: {json.dumps({'reasoning': wrapped_reasoning})}\n\n"

                    # Send citations if any were collected
                    if citations:
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

                        logger.info(f"[CITATIONS] Sending {len(unique_citations)} unique citations")
                        yield f"data: {json.dumps({'citations': unique_citations})}\n\n"

                    # Save assistant message to database
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
