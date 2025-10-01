from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    """Health check endpoint for Databricks Apps"""
    return {"status": "healthy", "app": "BrickChat"}
