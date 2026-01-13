# TTS Volume Caching Design

## Overview

Implement lazy caching of TTS audio files to Databricks Volumes, scoped per user. When a user plays audio for a message, the generated audio is saved to their Volume folder. Subsequent plays fetch from cache instead of regenerating.

## Goals

- Cache TTS audio to reduce API costs and latency on repeat plays
- User isolation via GUID-based paths and on-behalf-of token writes
- Transparent caching - same API, faster on repeat plays
- Graceful fallback for local development (no caching)

## Non-Goals

- Browsing/downloading TTS files on demand (removed from scope)
- Proactive TTS generation (only generate when user clicks play)

## Design

### Volume Path Structure

```
/Volumes/serverless_9cefok_catalog/sgfs/data/brickchat/tts_audio/{user_id}/{thread_id}/{message_id}.mp3
```

- One file per message (overwrites on voice change)
- User isolation via GUID-based user_id in path
- Files written using user's access token (on-behalf-of)

### Cache Metadata Storage

Store TTS cache info in the existing `chat_messages.metadata` JSONB field:

```json
{
  "tts_cache": {
    "volume_path": "/Volumes/serverless_9cefok_catalog/sgfs/data/brickchat/tts_audio/{user_id}/{thread_id}/{message_id}.mp3",
    "voice": "af_nicole",
    "provider": "replicate",
    "cached_at": "2025-01-12T10:30:00Z"
  }
}
```

### Request Flow

```
User clicks "Play" on message
       |
       v
Flutter calls POST /api/tts/speak
  { text, voice, provider, message_id, thread_id }
       |
       v
Backend checks: is Volume caching enabled?
  (DATABRICKS_VOLUME env var present + user authenticated with token)
       |
       +-- NO --> Generate audio, stream directly (current behavior)
       |
       +-- YES --> Check message metadata for tts_cache
                     |
                     +-- CACHED + same voice --> Fetch from Volume, stream
                     |
                     +-- NOT CACHED or voice changed:
                           1. Generate audio
                           2. Write to Volume (using user's token, overwrite=True)
                           3. Update message metadata with tts_cache info
                           4. Stream audio to client
```

### Caching Enabled Conditions

Caching is only enabled when ALL of these are true:
1. `DATABRICKS_VOLUME` environment variable is set
2. User has a valid access token (`user.is_authenticated == True`)
3. Request includes `message_id` and `thread_id`

Otherwise, falls back to direct streaming (current behavior).

## Implementation

### Backend Changes

#### 1. New Database Method (`database.py`)

```python
def update_message_tts_cache(self, message_id: str, tts_cache: Dict) -> bool:
    """Update message metadata with TTS cache info"""
    query = """
        UPDATE chat_messages
        SET metadata = metadata || %s
        WHERE message_id = %s
        RETURNING message_id
    """
    result = self.db.execute_query_one(
        query,
        (Json({"tts_cache": tts_cache}), message_id)
    )
    return result is not None

def get_message_tts_cache(self, message_id: str, user_id: str) -> Optional[Dict]:
    """Get TTS cache info for a message, verifying user ownership"""
    query = """
        SELECT metadata->'tts_cache' as tts_cache
        FROM chat_messages
        WHERE message_id = %s AND user_id = %s
    """
    result = self.db.execute_query_one(query, (message_id, user_id))
    return result['tts_cache'] if result and result['tts_cache'] else None
```

#### 2. Updated TTS Router (`routers/tts.py`)

```python
import io
import os
from datetime import datetime

DATABRICKS_VOLUME = os.environ.get('DATABRICKS_VOLUME', '')

def is_caching_enabled(user: UserContext) -> bool:
    """Check if Volume caching is available"""
    return bool(DATABRICKS_VOLUME) and user.is_authenticated

def get_volume_path(user_id: str, thread_id: str, message_id: str) -> str:
    """Construct the Volume path for a TTS file"""
    return f"{DATABRICKS_VOLUME}tts_audio/{user_id}/{thread_id}/{message_id}.mp3"

@router.post("/speak")
async def text_to_speech(request: dict, user: UserContext = Depends(get_current_user)):
    text = request.get("text", "").strip()
    voice = request.get("voice", "af_nicole")
    provider = request.get("provider", "replicate")
    message_id = request.get("message_id")
    thread_id = request.get("thread_id")

    # Check if caching is possible
    can_cache = (
        is_caching_enabled(user) and
        message_id and
        thread_id
    )

    if can_cache:
        # Check for cached audio
        cached = chat_db.get_message_tts_cache(message_id, user.user_id)

        if cached and cached.get("voice") == voice:
            # Cache hit - fetch from Volume
            try:
                workspace_client = user.get_workspace_client()
                with workspace_client.files.download(cached["volume_path"]).contents as f:
                    audio_data = f.read()
                return StreamingResponse(
                    iter([audio_data]),
                    media_type="audio/mpeg",
                    headers={"X-TTS-Cache": "hit"}
                )
            except Exception as e:
                logger.warning(f"Cache fetch failed, regenerating: {e}")

    # Generate audio (existing logic)
    audio_data, provider_used = await generate_tts_audio(text, voice, provider)

    if can_cache and audio_data:
        # Save to Volume and update metadata
        try:
            volume_path = get_volume_path(user.user_id, thread_id, message_id)
            workspace_client = user.get_workspace_client()

            audio_stream = io.BytesIO(audio_data)
            workspace_client.files.upload(volume_path, audio_stream, overwrite=True)

            chat_db.update_message_tts_cache(message_id, {
                "volume_path": volume_path,
                "voice": voice,
                "provider": provider_used,
                "cached_at": datetime.utcnow().isoformat()
            })
            logger.info(f"Cached TTS for message {message_id}")
        except Exception as e:
            logger.warning(f"Failed to cache TTS: {e}")
            # Continue - still return the audio

    # Stream audio response
    return StreamingResponse(
        iter([audio_data]),
        media_type="audio/mpeg",
        headers={"X-TTS-Cache": "miss" if can_cache else "disabled"}
    )
```

### Flutter Changes

#### 1. Update `FastApiService.requestTts()` (`lib/core/services/fastapi_service.dart`)

```dart
static Future<http.Response> requestTts(
  String text, {
  String? provider,
  String? voice,
  String? messageId,
  String? threadId,
}) async {
  try {
    final url = Uri.parse('$baseUrl/api/tts/speak');
    final requestBody = {
      'text': text,
      if (provider != null) 'provider': provider,
      if (voice != null) 'voice': voice,
      if (messageId != null) 'message_id': messageId,
      if (threadId != null) 'thread_id': threadId,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );
    return response;
  } catch (e) {
    throw Exception('Error requesting TTS: $e');
  }
}
```

#### 2. Update TTS Call Site (`lib/features/chat/presentation/chat_home_page.dart`)

Pass message context when requesting TTS:

```dart
final response = await FastApiService.requestTts(
  messageText,
  voice: ttsVoice,
  messageId: message.id,
  threadId: currentThreadId,
);
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Volume write fails | Log warning, return audio anyway (no caching) |
| Volume read fails | Log warning, regenerate audio |
| Metadata update fails | Log warning, audio still returned |
| User not authenticated | Skip caching, stream directly |
| Missing message_id/thread_id | Skip caching, stream directly |

## Testing

### Local Development
- No `DATABRICKS_VOLUME` env var = caching disabled
- Works exactly as current implementation

### Deployed (Databricks Apps)
1. First play of a message: generates audio, saves to Volume, streams
2. Second play (same voice): fetches from Volume, streams (faster)
3. Play with different voice: regenerates, overwrites file, updates metadata
4. Different user: cannot access other user's files (GUID paths + on-behalf-of writes)

## Files to Modify

| File | Changes |
|------|---------|
| `backend/database.py` | Add `update_message_tts_cache()` and `get_message_tts_cache()` methods |
| `backend/routers/tts.py` | Add caching logic to `/speak` endpoint |
| `deployment/database.py` | Port database changes |
| `deployment/routers/tts.py` | Port TTS router changes |
| `lib/core/services/fastapi_service.dart` | Add `messageId` and `threadId` params to `requestTts()` |
| `lib/features/chat/presentation/chat_home_page.dart` | Pass message context to TTS requests |
