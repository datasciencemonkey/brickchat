from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import os
from dotenv import load_dotenv

# Import routers
from routers import health, chat, tts

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

# Include routers
app.include_router(health.router)
app.include_router(chat.router)
app.include_router(tts.router)

# Define API routes first, then serve static files
# This ensures /api routes are matched before the catch-all static files

@app.get("/")
async def read_index():
    """Serve the main Flutter web app"""
    if os.path.exists("build/web/index.html"):
        return FileResponse("build/web/index.html")
    return {"message": "BrickChat FastAPI Backend", "status": "running"}

# Mount static files AFTER API routes to avoid conflicts
# This serves all the Flutter web assets (JS, CSS, images, etc.)
if os.path.exists("build/web"):
    app.mount("/assets", StaticFiles(directory="build/web/assets"), name="assets")
    app.mount("/", StaticFiles(directory="build/web", html=True), name="static_files")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
