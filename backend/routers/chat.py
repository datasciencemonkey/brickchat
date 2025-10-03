from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from openai import OpenAI
import os
from dotenv import load_dotenv
import json
import re
load_dotenv()

router = APIRouter(prefix="/api/chat", tags=["chat"])

# Databricks configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', 'https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL')

# Initialize Databricks client
client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
)


@router.post("/send")
async def send_message(message: dict):
    """Send a chat message to Databricks endpoint with conversation history"""
    try:
        # Extract the message text from the request
        message_text = message.get("message", "").strip()
        if not message_text:
            raise HTTPException(status_code=400, detail="Message text is required")

        # Extract conversation history (optional)
        conversation_history = message.get("conversation_history", [])

        # Extract stream parameter (defaults to True for backward compatibility)
        use_streaming = message.get("stream", True)

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
            # Create streaming response with buffering for complete markdown structures
            def generate_stream():
                try:
                    buffer = ""
                    # Regex pattern to match sentence/paragraph boundaries
                    # Matches: period/question/exclamation followed by space or newline, or double newlines
                    boundary_pattern = re.compile(r'([.!?]\s+|\n\n)')

                    # Pattern to remove citation/reference artifacts like [^TIBB-1]12 or [^hEnJ-6]4
                    citation_pattern = re.compile(r'\[\^[A-Za-z0-9\-]+\]\d*')

                    for chunk in response:
                        # Handle ResponseTextDeltaEvent chunks
                        if hasattr(chunk, 'delta') and chunk.delta:
                            content = chunk.delta
                            buffer += content

                            # Check if buffer contains a natural breakpoint
                            match = boundary_pattern.search(buffer)
                            if match:
                                # Find the position after the boundary
                                split_pos = match.end()

                                # Send everything up to and including the boundary
                                to_send = buffer[:split_pos]
                                buffer = buffer[split_pos:]

                                # Clean citation artifacts before sending
                                to_send = citation_pattern.sub('', to_send)

                                yield f"data: {json.dumps({'content': to_send})}\n\n"

                    # Send any remaining buffered content
                    if buffer:
                        # Clean citation artifacts before sending
                        buffer = citation_pattern.sub('', buffer)
                        yield f"data: {json.dumps({'content': buffer})}\n\n"

                    # Send end signal
                    yield f"data: {json.dumps({'done': True})}\n\n"
                except Exception as e:
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
            # Non-streaming response - extract content from response object
            try:
                full_content = ""
                if hasattr(response, 'output') and response.output:
                    for output_message in response.output:
                        if hasattr(output_message, 'content') and output_message.content:
                            for content_item in output_message.content:
                                if hasattr(content_item, 'text') and content_item.text:
                                    full_content += content_item.text

                return {
                    "response": full_content,
                    "backend": "databricks",
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
