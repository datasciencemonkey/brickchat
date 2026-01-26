# CLAUDE.md

## Quick Reference

**Aladdin** (formerly BrickChat): Flutter web/desktop chat app + Python FastAPI backend connecting to Databricks serving endpoints. Named "Aladdin" because it rhymes with "all-add-in" — a single interface to control the chaos.

| Task | Command |
|------|---------|
| Run backend | `uv run python app.py` (port 8000) |
| Build frontend | `flutter build web --wasm` |
| Access app | `http://localhost:8000` |
| Run tests | `flutter test` |
| Install deps | `flutter pub get` / `uv sync` |

---

## Critical Rules

### Authentication (NEVER violate these)
- **NEVER** use user's `X-Forwarded-Access-Token` for API calls
- **ALWAYS** use `DATABRICKS_TOKEN` (app's service principal) for all Databricks API calls
- User token is for identification only (logging, thread ownership)

### API Patterns
- Chat endpoint uses `responses.create()` (not `chat.completions.create()`)
- Streaming via Server-Sent Events (SSE)
- OpenAI-compatible format for Databricks endpoints

### WASM Compatibility
- Use `dart:js_interop` (not `dart:html`)
- Use `file_selector` (not `file_picker`)

### Code Changes
- **NEVER** modify conversation history logic in `app.py`
- **ALWAYS** work in `backend/` first, then port to `deployment/`

---

## Folder Conventions

| Folder | Purpose |
|--------|---------|
| `backend/` | Development backend (work here first) |
| `deployment/` | Production backend (port from backend/) |
| `vision/` | Strategic/vision documents |
| `plan_mode_plans/` | Implementation plans |
| `skills/` | Claude Code workflow skills |

---

## Architecture

```
lib/
├── core/
│   ├── services/fastapi_service.dart    # Backend API client
│   └── theme/                           # Theme system (app_colors, gradients, etc.)
├── features/
│   ├── chat/presentation/               # Main chat UI
│   ├── autonomous/                      # Agent routing (Level 2)
│   └── settings/                        # User preferences
└── shared/widgets/                      # Reusable components

deployment/
├── app.py                               # FastAPI entry point
├── routers/
│   ├── chat.py                          # Chat endpoints
│   ├── autonomous.py                    # Agent discovery & routing
│   └── auth.py                          # User context extraction
├── database.py                          # PostgreSQL connections
└── migrations/                          # SQL schema files
```

---

## Autonomous Mode (Level 2)

Current implementation routes user messages to Databricks Agent Bricks:

```
User Message → Claude Router → Select Best Agent → Agent Brick → Response
```

**Key endpoints**:
- `POST /api/agents/discover` - Discover Agent Bricks (admin)
- `GET /api/agents` - Get enabled agents
- `POST /api/agents/chat/autonomous` - Route message to agent

**Database table**: `autonomous_agents` (agent_id, endpoint_url, status, router_metadata)

---

## Skills

### `/brand-theme`
Configure app branding via Q&A. Outputs `assets/config/theme_config.json`.

### `/apply-theme`
Apply theme config to Dart files. Run `/brand-theme` first.

---

## State Management

- **Riverpod** for all state management
- **SharedPreferences** for persistence (theme, settings)
- **GetIt** for service location

---

## Important Patterns

### Auth Usage in Routers
```python
from auth import get_current_user, UserContext

@router.post("/endpoint")
async def my_endpoint(user: UserContext = Depends(get_current_user)):
    # user.user_id, user.email for identification only
    client = OpenAI(api_key=DATABRICKS_TOKEN, base_url=DATABRICKS_BASE_URL)
```

### Chat API (Responses API)
```python
response = client.responses.create(
    model=DATABRICKS_MODEL,
    input=[{"role": "user", "content": "..."}],
    stream=True
)
```

---

# Reminders
- Do what has been asked; nothing more, nothing less
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files over creating new ones
- Use `uv` for all Python operations
