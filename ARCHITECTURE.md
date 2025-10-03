# BrickChat - Architecture Overview

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATABRICKS APPS                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     BrickChat Application                          │  │
│  │                                                                    │  │
│  │  ┌──────────────────┐         ┌──────────────────────────────┐   │  │
│  │  │  Flutter Web UI  │◄────────│   FastAPI Backend            │   │  │
│  │  │  (build/web/)    │  Static │   (app.py)                   │   │  │
│  │  │                  │  Files  │                               │   │  │
│  │  │  - Chat UI       │         │  Routes:                      │   │  │
│  │  │  - Voice Input   │         │  ├─ /api/health              │   │  │
│  │  │  - Settings      │         │  ├─ /api/chat/send (SSE)     │   │  │
│  │  │  - TTS Player    │         │  └─ /api/tts/generate        │   │  │
│  │  └──────────────────┘         └──────────────────────────────┘   │  │
│  │         │                                   │                      │  │
│  │         │ HTTP/HTTPS                        │ API Calls            │  │
│  │         └───────────────────────────────────┘                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
        ┌─────────────────┐ ┌─────────────┐ ┌──────────────┐
        │  Databricks AI  │ │  Deepgram   │ │  Replicate   │
        │  Serving        │ │  TTS API    │ │  TTS API     │
        │  Endpoint       │ │             │ │  (Kokoro)    │
        │  (ka-4b190238)  │ │             │ │              │
        └─────────────────┘ └─────────────┘ └──────────────┘
```

## Component Breakdown

### 1. Frontend (Flutter Web - WASM)

```
lib/
├── main.dart                          # App entry point with Riverpod
├── core/
│   ├── constants/app_constants.dart   # Configuration & API endpoints
│   ├── services/
│   │   └── fastapi_service.dart       # Backend API client
│   └── theme/                         # Theme system (light/dark)
│       ├── app_theme.dart
│       ├── theme_provider.dart
│       └── app_colors.dart
├── features/
│   ├── chat/
│   │   └── presentation/
│   │       └── chat_home_page.dart    # Main chat interface
│   └── settings/
│       ├── presentation/
│       │   └── settings_page.dart     # Settings UI
│       └── providers/
│           └── settings_provider.dart # Settings state management
└── shared/
    └── widgets/
        ├── speech_to_text_widget.dart # Voice input
        └── theme_toggle.dart          # Theme switcher
```

**Key Features:**
- Material 3 design with custom Databricks branding
- Riverpod state management
- Real-time streaming chat responses
- Voice input (Speech-to-Text)
- TTS playback (Text-to-Speech)
- Theme persistence (SharedPreferences)

### 2. Backend (FastAPI)

```
app.py                              # Main FastAPI application
├── CORS middleware                 # Allow cross-origin requests
├── WASM headers middleware         # Flutter WASM support
├── Static file serving             # Serve Flutter build/web
└── API Routers:
    ├── routers/health.py           # Health check endpoint
    ├── routers/chat.py             # Chat with Databricks AI
    └── routers/tts.py              # Text-to-Speech generation
```

**Key Features:**
- OpenAI-compatible API client for Databricks
- Server-Sent Events (SSE) for streaming responses
- Dual TTS provider support (Deepgram/Replicate)
- Environment-based configuration

### 3. External Services

#### Databricks AI Serving Endpoint
```
Endpoint: ka-4b190238-endpoint
Base URL: https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints
Protocol: OpenAI-compatible API
Features: Chat completions with streaming
```

#### Deepgram TTS
```
Provider: Deepgram Aura
Voices: 13 options (Thalia, Asteria, Luna, etc.)
Format: MP3 audio
Speed: ~1-2 seconds
```

#### Replicate TTS
```
Provider: Kokoro-82M model
Voices: 18 options (Nicole, Bella, Adam, etc.)
Format: MP3 audio
Speed: <1 seconds
```

## Data Flow Diagrams

### Chat Message Flow (Streaming)

```
User Input
   │
   ▼
┌─────────────────┐
│ Flutter UI      │
│ chat_home_page  │
└─────────────────┘
   │
   │ 1. Send message + conversation history
   │
   ▼
┌─────────────────┐
│ FastAPI         │
│ /api/chat/send  │
└─────────────────┘
   │
   │ 2. OpenAI client.chat.completions.create(stream=True)
   │
   ▼
┌──────────────────┐
│ Databricks       │
│ Serving Endpoint │
└──────────────────┘
   │
   │ 3. Stream response chunks (SSE)
   │
   ▼
┌─────────────────┐
│ FastAPI         │
│ yield chunks    │
└─────────────────┘
   │
   │ 4. Server-Sent Events
   │
   ▼
┌─────────────────┐
│ Flutter UI      │
│ Display message │
│ word-by-word    │
└─────────────────┘
```

### Text-to-Speech Flow

```
User clicks speaker icon
   │
   ▼
┌─────────────────┐
│ Flutter UI      │
│ _playTextToSpeech │
└─────────────────┘
   │
   │ 1. POST /api/tts/generate
   │    { text, provider, voice }
   │
   ▼
┌─────────────────┐
│ FastAPI         │
│ routers/tts.py  │
└─────────────────┘
   │
   ├──────────────┬──────────────┐
   │              │              │
   ▼              ▼              │
┌───────────┐ ┌──────────┐      │
│ Deepgram  │ │ Replicate│      │
│ API       │ │ API      │      │
└───────────┘ └──────────┘      │
   │              │              │
   │ 2. Generate  │              │
   │    audio     │              │
   │              │              │
   └──────┬───────┘              │
          │                      │
          │ 3. Return audio URL  │
          │                      │
          ▼                      │
   ┌─────────────────┐           │
   │ FastAPI         │           │
   │ Return response │           │
   └─────────────────┘           │
          │                      │
          │ 4. { audio_url }     │
          │                      │
          ▼                      │
   ┌─────────────────┐           │
   │ Flutter UI      │           │
   │ Audio().play()  │◄──────────┘
   └─────────────────┘
```

### Voice Input Flow

```
User clicks microphone
   │
   ▼
┌─────────────────┐
│ Flutter UI      │
│ speech_to_text  │
│ _widget.dart    │
└─────────────────┘
   │
   │ 1. Request microphone permission
   │
   ▼
┌─────────────────┐
│ Browser API     │
│ getUserMedia()  │
└─────────────────┘
   │
   │ 2. Permission granted
   │
   ▼
┌─────────────────┐
│ speech_to_text  │
│ plugin          │
└─────────────────┘
   │
   │ 3. Listen & transcribe (on-device)
   │
   ▼
┌─────────────────┐
│ Flutter UI      │
│ onTextRecognized│
└─────────────────┘
   │
   │ 4. Send as chat message
   │
   ▼
(Continue with Chat Message Flow)
```

## State Management (Riverpod)

```
┌────────────────────────────────────────────────────┐
│              ProviderScope (main.dart)             │
└────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────┐
│ themeProvider│ │streamResults│ │ eagerMode    │
│              │ │Provider     │ │ Provider     │
│ (Theme mode) │ │ (Stream on) │ │ (Auto-TTS)   │
└──────────────┘ └─────────────┘ └──────────────┘
        │               │               │
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────┐
│SharedPrefs   │ │SharedPrefs  │ │SharedPrefs   │
│theme_mode    │ │stream_mode  │ │eager_mode    │
└──────────────┘ └─────────────┘ └──────────────┘
```

**Provider Types:**
- `StateNotifierProvider` - Mutable state with history
- `Provider` - Computed/derived values
- Extensions for convenient access (`ref.streamResults`)

## Security & Configuration

### Environment Variables (app.yaml)

```yaml
env:
  - name: DATABRICKS_TOKEN
    value: "{{secrets/brickchat-secrets/databricks-token}}"
  - name: DATABRICKS_BASE_URL
    value: "https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints"
  - name: DATABRICKS_MODEL
    value: "ka-4b190238-endpoint"
  - name: DEEPGRAM_API_KEY
    value: "{{secrets/brickchat-secrets/deepgram-api-key}}"
  - name: REPLICATE_API_TOKEN
    value: "{{secrets/brickchat-secrets/replicate-api-token}}"
```

### Secrets Management

```
Databricks Workspace
   │
   ▼
Secret Scope: brickchat-secrets
   ├── databricks-token
   ├── deepgram-api-key
   └── replicate-api-token
```

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Local Development                                       │
│  ┌────────────────┐         ┌─────────────────────┐    │
│  │ Flutter Dev    │         │ Backend Dev         │    │
│  │ flutter run    │         │ uv run python app.py│    │
│  │ localhost:XXXX │◄───────►│ localhost:8000      │    │
│  └────────────────┘         └─────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                       │
                       │ ./deploy.sh
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  Databricks Apps Production                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Single Unified App                               │  │
│  │  URL: /apps/brickchat                            │  │
│  │  ┌────────────┐  ┌────────────┐                 │  │
│  │  │ Flutter    │  │ FastAPI    │                 │  │
│  │  │ Static     │◄─┤ Backend    │                 │  │
│  │  │ Files      │  │ API        │                 │  │
│  │  └────────────┘  └────────────┘                 │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Technology Stack

### Frontend
- **Framework**: Flutter 3.8.1+
- **Language**: Dart 3.8.1+
- **Build Target**: Web (WASM)
- **State Management**: Riverpod 2.6.1
- **UI**: Material 3 + flutter_chat_ui
- **Storage**: SharedPreferences
- **HTTP**: http package
- **Voice**: speech_to_text plugin

### Backend
- **Framework**: FastAPI 0.104.1+
- **Language**: Python 3.8+
- **Server**: Uvicorn
- **AI Client**: OpenAI SDK (Databricks-compatible)
- **TTS**: Deepgram SDK, Replicate SDK
- **Config**: python-dotenv

### Infrastructure
- **Platform**: Databricks Apps (Serverless)
- **Compute**: Auto-scaling serverless compute
- **Storage**: Ephemeral (no persistent storage)
- **Secrets**: Databricks Secret Manager
- **Networking**: HTTPS with CORS support

## Performance Characteristics

### Response Times
- **Health Check**: < 100ms
- **Chat (Non-Streaming)**: 2-5 seconds
- **Chat (Streaming)**: First token ~500ms, complete ~3-5s
- **TTS (Deepgram)**: 1-2 seconds
- **TTS (Replicate)**: <1 seconds
- **Voice Input**: Real-time (on-device processing)

### Resource Usage
- **Flutter Build**: 31 MB total, 6.7 MB largest file
- **Backend Code**: 60 KB
- **Memory**: ~200-500 MB (estimated)
- **Bandwidth**: ~2-5 MB per session

## Scalability

```
User Load → Databricks Apps → Auto-scaling Serverless Compute
  │              │                       │
  1-10 users     └─► Single instance     │
  10-100 users       Multiple instances ─┘
  100+ users         Dynamic scaling
```

## Error Handling

### Frontend
- Network errors → User-friendly messages
- API timeouts → Retry mechanism
- Voice permission denied → Fallback to text input
- TTS failures → Silent failure with error log

### Backend
- Databricks API errors → 500 with error details
- Missing secrets → 503 Service Unavailable
- Invalid input → 400 Bad Request
- Rate limits → 429 Too Many Requests

---

**Architecture Version**: 1.0.0
**Last Updated**: October 2025
