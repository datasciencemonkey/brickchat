from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
import os
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

# Databricks configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN','')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', 'https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL', 'ka-0b79c13a-endpoint') # this can be whatever....

# Initialize Databricks client
databricks_client = None
if DATABRICKS_TOKEN:
    databricks_client = OpenAI(
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

        # Check if Databricks client is configured
        if not databricks_client:
            raise HTTPException(
                status_code=503,
                detail="Databricks client not configured. Please set DATABRICKS_TOKEN environment variable."
            )

        # Prepare the input messages with conversation history
        input_messages = []

        # Add conversation history if provided
        if conversation_history:
            for msg in conversation_history:
                input_messages.append({
                    "role": msg.get("role", "user"),
                    "content": msg.get("content", "")
                })

        # Add the current message
        input_messages.append({
            "role": "user",
            "content": message_text
        })

        # Send message to Databricks using OpenAI client format
        response = databricks_client.responses.create(
            model=DATABRICKS_MODEL,
            input=input_messages
        )

        # Extract response text
        response_text = response.output[0].content[0].text

        return {
            "response": response_text,
            "backend": "databricks",
            "status": "success"
        }

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
