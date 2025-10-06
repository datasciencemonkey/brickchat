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
                    full_response_debug = ""  # Accumulate entire response for debugging

                    # Regex pattern to match sentence/paragraph boundaries
                    # Matches: period/question/exclamation followed by space or newline, or double newlines
                    boundary_pattern = re.compile(r'([.!?]\s+|\n\n)')

                    # Pattern to remove citation artifacts that have trailing numbers (like [^ID]12)
                    # This preserves clean footnote references like [^ID] that should stay in the text
                    citation_artifact_pattern = re.compile(r'\[\^[A-Za-z0-9\-]+\](\d+)')

                    # Pattern to detect footnote definitions: [^ID]: content
                    # Matches footnotes at start of line or after newline
                    footnote_pattern = re.compile(r'(?:^|\n)\[\^([A-Za-z0-9\-]+)\]:\s*(.+?)(?=\n\[\^|$)', re.DOTALL | re.MULTILINE)

                    # Map to track footnote references for numbering
                    footnote_reference_map = {}

                    for chunk in response:
                        # Handle ResponseTextDeltaEvent chunks
                        if hasattr(chunk, 'delta') and chunk.delta:
                            content = chunk.delta
                            full_response_debug += content  # Accumulate for logging
                            print(f"[RAW CHUNK] {repr(content)}")  # Debug: see raw chunks
                            buffer += content

                            # Check if buffer contains a natural breakpoint
                            match = boundary_pattern.search(buffer)
                            if match:
                                # Find the position after the boundary
                                split_pos = match.end()

                                # Send everything up to and including the boundary
                                to_send = buffer[:split_pos]
                                buffer = buffer[split_pos:]

                                # Remove citation artifacts with trailing numbers (e.g., [^ID]12)
                                to_send = citation_artifact_pattern.sub('', to_send)

                                yield f"data: {json.dumps({'content': to_send})}\n\n"

                    # Process remaining buffered content
                    if buffer:
                        # Extract footnotes from the buffer
                        footnotes = []
                        footnote_matches = footnote_pattern.findall(buffer)
                        print(f"[FOOTNOTE DETECTION] Found {len(footnote_matches)} footnotes")

                        # Build footnote reference map (ID -> number)
                        for idx, (footnote_id, footnote_content) in enumerate(footnote_matches, 1):
                            footnote_reference_map[footnote_id] = idx
                            footnotes.append({
                                'id': footnote_id,
                                'number': idx,
                                'content': footnote_content.strip()
                            })
                            print(f"[FOOTNOTE {idx}] [{footnote_id}]: {footnote_content.strip()[:50]}...")

                        # Remove footnotes definitions from main content
                        main_content = footnote_pattern.sub('', buffer)

                        # Remove citation artifacts with trailing numbers
                        main_content = citation_artifact_pattern.sub('', main_content)

                        # Convert footnote references [^ID] to superscript numbers
                        def replace_footnote_ref(match):
                            footnote_id = match.group(1)
                            if footnote_id in footnote_reference_map:
                                num = footnote_reference_map[footnote_id]
                                return f'<sup><a href="#footnote-{num}">{num}</a></sup>'  # HTML superscript with link
                            return match.group(0)  # Keep original if not found

                        footnote_ref_pattern = re.compile(r'\[\^([A-Za-z0-9\-]+)\]')
                        main_content = footnote_ref_pattern.sub(replace_footnote_ref, main_content)

                        # Send main content if any
                        if main_content.strip():
                            yield f"data: {json.dumps({'content': main_content})}\n\n"

                        # Send footnotes separately if any
                        if footnotes:
                            print(f"[SENDING FOOTNOTES] Sending {len(footnotes)} footnotes to client")
                            yield f"data: {json.dumps({'footnotes': footnotes})}\n\n"

                    # Log complete raw response for analysis
                    print("\n" + "="*80)
                    print("[COMPLETE RAW RESPONSE]")
                    print("="*80)
                    print(full_response_debug)
                    print("="*80 + "\n")

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
