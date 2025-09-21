from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

app = FastAPI(title="BrickChat Web App", version="1.0.0")

# Mount static files directory
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def read_index():
    """Serve the main Flutter web app"""
    return FileResponse("static/index.html")

@app.get("/health")
async def health_check():
    """Health check endpoint for Databricks Apps"""
    return {"status": "healthy", "app": "BrickChat"}

# Optional: Add API endpoints for your chat functionality
@app.get("/api/chat/messages")
async def get_messages():
    """Get chat messages - implement your chat logic here"""
    return {"messages": []}

@app.post("/api/chat/send")
async def send_message(message: dict):
    """Send a chat message - implement your chat logic here"""
    return {"status": "message_sent", "message": message}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
