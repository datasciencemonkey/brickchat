from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import os
import logging
from dotenv import load_dotenv

# Import routers
from routers import health, chat, tts, feedback, auth

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="BrickChat Web App", version="1.0.0")

# Log startup information
logger.info("Starting BrickChat FastAPI Backend")
logger.info(f"Current working directory: {os.getcwd()}")
logger.info(f"Looking for build at: build/web or ../build/web")
if os.path.exists("build/web"):
    logger.info("✓ Found build at: build/web")
elif os.path.exists("../build/web"):
    logger.info("✓ Found build at: ../build/web")
else:
    logger.warning("✗ Flutter build not found!")

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

    # Only add WASM headers for HTML pages, not for API routes
    # This prevents CORS issues with API endpoints
    if request.url.path == "/" or request.url.path.endswith(".html"):
        # Required headers for Flutter WASM multi-threading support
        response.headers["Cross-Origin-Embedder-Policy"] = "credentialless"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"

    return response

# Include routers
app.include_router(health.router)
app.include_router(chat.router)
app.include_router(tts.router)
app.include_router(feedback.router)
app.include_router(auth.router)

# Define API routes first, then serve static files
# This ensures /api routes are matched before the catch-all static files

@app.get("/debug/info")
async def debug_info():
    """Diagnostic endpoint to check deployment status"""
    return {
        "status": "running",
        "cwd": os.getcwd(),
        "build_exists": {
            "build/web": os.path.exists("build/web"),
            "../build/web": os.path.exists("../build/web"),
        },
        "index_exists": {
            "build/web/index.html": os.path.exists("build/web/index.html"),
            "../build/web/index.html": os.path.exists("../build/web/index.html"),
        },
        "files_in_cwd": os.listdir(".")[:20] if os.path.exists(".") else []
    }

@app.get("/")
async def read_index():
    """Serve the main Flutter web app"""
    # Try deployment path first, then development path
    if os.path.exists("build/web/index.html"):
        logger.info("Serving index from: build/web/index.html")
        return FileResponse("build/web/index.html")
    elif os.path.exists("../build/web/index.html"):
        logger.info("Serving index from: ../build/web/index.html")
        return FileResponse("../build/web/index.html")

    logger.error("Flutter build not found! Cannot serve app.")
    return {
        "error": "Flutter build not found",
        "message": "BrickChat FastAPI Backend is running, but Flutter build is missing",
        "status": "backend_only",
        "hint": "Visit /debug/info for diagnostics"
    }

# Mount static files AFTER API routes to avoid conflicts
# This serves all the Flutter web assets (JS, CSS, images, etc.)
# Check deployment path first, then development path
if os.path.exists("build/web"):
    app.mount("/assets", StaticFiles(directory="build/web/assets"), name="assets")
    app.mount("/", StaticFiles(directory="build/web", html=True), name="static_files")
elif os.path.exists("../build/web"):
    app.mount("/assets", StaticFiles(directory="../build/web/assets"), name="assets")
    app.mount("/", StaticFiles(directory="../build/web", html=True), name="static_files")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
