# Backend Tests

This folder contains test scripts for validating the BrickChat backend functionality.

## Test Scripts

### 1. `test_streaming_modes.py`
Tests the FastAPI `/api/chat/send` endpoint with different streaming modes:

- **Non-streaming mode** (`stream=false`): Tests complete JSON response
- **Streaming mode** (`stream=true`): Tests Server-Sent Events streaming
- **Default mode** (no stream parameter): Tests default behavior (should be streaming)
- **Health endpoint**: Tests `/health` endpoint

**Usage:**
```bash
cd backend
python tests/test_streaming_modes.py
```

### 2. `test_databricks_api.py`
Tests direct interaction with Databricks API:

- **Streaming API**: Tests `client.responses.create(stream=True)`
- **Non-streaming API**: Tests `client.responses.create(stream=False)`
- **Conversation history**: Tests multi-turn conversations

**Usage:**
```bash
cd backend
python tests/test_databricks_api.py
```

## Requirements

- **Environment variables**: Set in `.env` file
  - `DATABRICKS_TOKEN`
  - `DATABRICKS_BASE_URL`
  - `DATABRICKS_MODEL`

- **Python packages**: Install with `uv add requests python-dotenv openai`

- **Running server**: For API tests, ensure the FastAPI server is running on port 8000

## Expected Results

All tests should pass with ✅ status when:
1. Backend server is running (`python app.py`)
2. Environment variables are properly configured
3. Databricks endpoint is accessible

## Test Output

Tests provide detailed output including:
- HTTP status codes
- Response formats (JSON vs Server-Sent Events)
- Content length and previews
- Error messages for debugging

## Integration with Development

These tests validate:
- API endpoint functionality
- Databricks integration
- Streaming vs non-streaming modes
- Error handling
- Response format consistency