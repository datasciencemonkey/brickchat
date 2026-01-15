# BrickChat

A production-ready AI chat interface for Databricks serving endpoints. Deploy as a Databricks App with SSO authentication, persistent conversations, and enterprise features.

## What BrickChat Does

BrickChat provides a complete chat experience for interacting with AI agents hosted on Databricks:

- **Connects to Databricks AI serving endpoints** using OpenAI-compatible API format
- **Streams responses in real-time** with Server-Sent Events (SSE)
- **Persists all conversations** to PostgreSQL with thread management and search
- **Authenticates users automatically** via Databricks Apps on-behalf-of flow
- **Supports voice input** with browser-native speech-to-text
- **Provides text-to-speech** playback via Deepgram or Replicate APIs
- **TalkToMyPDF**: Upload and chat with PDF/TXT documents using multimodal AI

## Architecture

```mermaid
flowchart TB
    subgraph "Databricks Apps"
        subgraph "BrickChat Application"
            UI[Flutter Web UI<br/>WASM Build]
            API[FastAPI Backend<br/>Port 8000]
            DB[(PostgreSQL<br/>Chat History)]
        end
    end

    UI -->|HTTP/SSE| API
    API -->|SQL| DB
    API -->|OpenAI API| DAI[Databricks AI<br/>Serving Endpoint]
    API -->|TTS API| DG[Deepgram]
    API -->|TTS API| REP[Replicate]
    API -->|Files API| UC[(Unity Catalog<br/>Volumes)]
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed diagrams and data flows.

## Quick Start: Deploy to Databricks

### Prerequisites

- Databricks workspace with Apps enabled
- [Databricks CLI](https://docs.databricks.com/dev-tools/cli/index.html) installed and configured
- PostgreSQL database accessible from Databricks
- Flutter SDK 3.8.1+ installed

### Step 1: Configure Secrets

Create a secret scope and add required secrets:

```bash
# Create secret scope
databricks secrets create-scope brickchat-secrets

# Add secrets (you'll be prompted for values)
databricks secrets put-secret brickchat-secrets databricks-token
databricks secrets put-secret brickchat-secrets pghost
databricks secrets put-secret brickchat-secrets pg-pass
databricks secrets put-secret brickchat-secrets deepgram-api-key      # Optional: for TTS
databricks secrets put-secret brickchat-secrets replicate-api-token   # Optional: for TTS
```

### Step 2: Update Configuration

Edit `deployment/app.yaml` to match your environment:

```yaml
env:
  - name: DATABRICKS_MODEL
    value: "your-serving-endpoint-name"  # Update this
  - name: DATABRICKS_BASE_URL
    value: "https://your-workspace.cloud.databricks.com/serving-endpoints"  # Update this
```

### Step 3: Build and Deploy

```bash
# Build Flutter WASM
flutter build web --wasm

# Update deployment folder
./deployment/update_deployment.sh

# Deploy to Databricks Apps
databricks apps deploy brickchat --source-code-path ./deployment
```

### Step 4: Access Your App

After deployment completes, access BrickChat at:
```
https://your-workspace.cloud.databricks.com/apps/brickchat
```

## Quick Start: Local Development

### Backend

```bash
cd backend

# Create .env file from example
cp .env.example .env
# Edit .env with your credentials

# Install dependencies and run
uv pip install -r requirements.txt
uv run python app.py
```

Backend runs at `http://localhost:8000`

### Frontend (for UI development)

```bash
# Run Flutter in Chrome
flutter run -d chrome
```

For full-stack development, the backend serves the Flutter build at `http://localhost:8000`.

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `DATABRICKS_TOKEN` | Personal access token for Databricks API | Yes |
| `DATABRICKS_BASE_URL` | Serving endpoint base URL | Yes |
| `DATABRICKS_MODEL` | Model/endpoint name | Yes |
| `DATABRICKS_DOCUMENT_MODEL` | Model for document Q&A (default: `databricks-claude-sonnet-4-5`) | No |
| `DOCUMENTS_VOLUME_PATH` | Unity Catalog volume path for documents (e.g., `/Volumes/catalog/schema/volume`) | No |
| `PGHOST` | PostgreSQL hostname | Yes |
| `PGDATABASE` | Database name (default: `brickchat`) | Yes |
| `PGUSER` | Database username | Yes |
| `PG_PASS` | Database password | Yes |
| `PGPORT` | Database port (default: `5432`) | No |
| `DEEPGRAM_API_KEY` | Deepgram API key for TTS | No |
| `REPLICATE_API_TOKEN` | Replicate API token for TTS | No |

### Database Setup

Apply the schema to your PostgreSQL database:

```bash
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f deployment/schema.sql
```

See [deployment/postgres_setup.md](deployment/postgres_setup.md) for detailed setup instructions.

## Features

### Chat
- Real-time streaming responses with typing indicators
- Conversation threading with history and search
- Message feedback (like/dislike) with persistence
- Markdown rendering with code syntax highlighting
- Collapsible reasoning sections for AI transparency

### TalkToMyPDF (Document Q&A)
- Upload PDF and TXT files (up to 10MB each, max 10 per thread)
- Documents stored securely in Unity Catalog volumes
- Chat with your documents using multimodal AI (Claude Sonnet 4.5)
- Per-user, per-thread document isolation
- Automatic document context injection into conversations

### Voice & Audio
- Speech-to-text via browser Web Speech API
- Text-to-speech with 18+ voice options (Deepgram Aura, Replicate Kokoro)
- Eager mode for automatic TTS playback

### Interface
- Light and dark themes with system preference detection
- Responsive design for web and desktop
- Professional Databricks-inspired branding

### Enterprise
- SSO authentication via Databricks Apps headers
- On-behalf-of API calls with user context
- PostgreSQL-backed persistence with connection pooling
- Unity Catalog integration for secure document storage

## Project Structure

```
brickchat/
├── lib/                    # Flutter frontend (Dart)
│   ├── core/              # Services, theme, constants
│   ├── features/          # Chat, settings pages
│   └── shared/            # Reusable widgets
├── backend/               # FastAPI backend (Python) - for development
│   ├── routers/           # API endpoints (chat, tts, feedback, documents)
│   ├── app.py             # Main application
│   ├── database.py        # PostgreSQL connection
│   └── document_service.py # Document storage and model API
├── deployment/            # Production deployment files
│   ├── app.yaml           # Databricks Apps config
│   ├── build/             # Flutter WASM build output
│   └── routers/           # API endpoints (production paths)
└── ARCHITECTURE.md        # Detailed architecture documentation
```

## Troubleshooting

See [deployment/TROUBLESHOOTING.md](deployment/TROUBLESHOOTING.md) for common issues and solutions.

## Support

For issues or feature requests, contact your Databricks administrator or open an issue in the repository.
