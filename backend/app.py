from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
import os
import json
from dotenv import load_dotenv
load_dotenv()

app = FastAPI(title="BrickChat Web App", version="1.0.0")

# Add CORS middleware to allow requests from Flutter development server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add middleware for Flutter WASM support
@app.middleware("http")
async def add_wasm_headers(request: Request, call_next):
    response = await call_next(request)

    # Required headers for Flutter WASM multi-threading support
    response.headers["Cross-Origin-Embedder-Policy"] = "credentialless"
    response.headers["Cross-Origin-Opener-Policy"] = "same-origin"

    return response

# Databricks configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN','')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', 'https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL') # this can be whatever....

# Initialize Databricks client
client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
)

@app.get("/health")
async def health_check():
    """Health check endpoint for Databricks Apps"""
    return {"status": "healthy", "app": "BrickChat"}

@app.post("/api/chat/send")
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
            # Create streaming response using the working pattern
            def generate_stream():
                try:
                    for chunk in response:
                        # Handle ResponseTextDeltaEvent chunks
                        if hasattr(chunk, 'delta') and chunk.delta:
                            content = chunk.delta
                            yield f"data: {json.dumps({'content': content})}\n\n"

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

# Define API routes first, then serve static files
# This ensures /api routes are matched before the catch-all static files

@app.get("/")
async def read_index():
    """Serve the main Flutter web app"""
    if os.path.exists("../build/web/index.html"):
        return FileResponse("../build/web/index.html")
    return {"message": "BrickChat FastAPI Backend", "status": "running"}

# Mount static files AFTER API routes to avoid conflicts
# This serves all the Flutter web assets (JS, CSS, images, etc.)
if os.path.exists("../build/web"):
    app.mount("/assets", StaticFiles(directory="../build/web/assets"), name="assets")
    app.mount("/", StaticFiles(directory="../build/web", html=True), name="static_files")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
