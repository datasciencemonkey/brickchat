# TTS Volume Caching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement lazy caching of TTS audio files to Databricks Volumes, scoped per user, with a user setting toggle.

**Architecture:** Backend checks cache on TTS request, fetches from Volume if cached (same voice), otherwise generates and caches. Flutter passes message context and user setting to enable caching.

**Tech Stack:** Python FastAPI, Databricks Volumes API, Flutter Riverpod, SharedPreferences

---

## Parallel Task Groups

Tasks within each group can run **in parallel**. Groups must run **sequentially**.

---

## Group 1: Backend Database + Flutter Provider (PARALLEL)

### Task 1A: Add Database Methods for TTS Cache

**Files:**
- Modify: `backend/database.py` (add 2 methods to `ChatDatabase` class, after line ~295)

**Step 1: Add `update_message_tts_cache` method**

Add after the `get_feedback_stats` method in `ChatDatabase` class:

```python
def update_message_tts_cache(self, message_id: str, tts_cache: Dict) -> bool:
    """Update message metadata with TTS cache info"""
    query = """
        UPDATE chat_messages
        SET metadata = COALESCE(metadata, '{}'::jsonb) || %s
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
    return result['tts_cache'] if result and result.get('tts_cache') else None
```

**Step 2: Verify syntax**

Run: `uv run python -c "import backend.database; print('OK')"`
Expected: OK

**Step 3: Commit**

```bash
git add backend/database.py
git commit -m "$(cat <<'EOF'
feat(backend): add database methods for TTS cache metadata

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1B: Add Flutter TTS Save-to-Volume Provider

**Files:**
- Modify: `lib/features/settings/providers/settings_provider.dart`

**Step 1: Add settings key**

Find the `SettingsKeys` class and add:

```dart
static const String ttsSaveToVolume = 'tts_save_to_volume';
```

**Step 2: Add provider and notifier**

Add after the `VoiceShortcutNotifier` class (before the `TtsSettingsRef` extension):

```dart
/// Provider for TTS save to volume setting
final ttsSaveToVolumeProvider = StateNotifierProvider<TtsSaveToVolumeNotifier, bool>((ref) {
  return TtsSaveToVolumeNotifier();
});

/// TTS save to volume setting notifier
class TtsSaveToVolumeNotifier extends StateNotifier<bool> {
  TtsSaveToVolumeNotifier() : super(false) {
    _loadSetting();
  }

  /// Load the TTS save to volume setting from SharedPreferences
  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saveToVolume = prefs.getBool(SettingsKeys.ttsSaveToVolume) ?? false;
      state = saveToVolume;
    } catch (e) {
      state = false;
    }
  }

  /// Toggle the save to volume setting
  Future<void> toggleSaveToVolume() async {
    await setSaveToVolume(!state);
  }

  /// Set the save to volume setting
  Future<void> setSaveToVolume(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsKeys.ttsSaveToVolume, enabled);
      state = enabled;
    } catch (e) {
      // If saving fails, state doesn't change
    }
  }
}
```

**Step 3: Add extension method**

Add to the `TtsSettingsRef` extension:

```dart
/// Get the current TTS save to volume setting
bool get ttsSaveToVolume => watch(ttsSaveToVolumeProvider);

/// Get the TTS save to volume notifier
TtsSaveToVolumeNotifier get ttsSaveToVolumeNotifier => read(ttsSaveToVolumeProvider.notifier);
```

**Step 4: Verify syntax**

Run: `flutter analyze lib/features/settings/providers/settings_provider.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/features/settings/providers/settings_provider.dart
git commit -m "$(cat <<'EOF'
feat(flutter): add TTS save to volume provider

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Group 2: Backend TTS Router + Flutter Settings UI (PARALLEL)

### Task 2A: Update Backend TTS Router with Caching Logic

**Files:**
- Modify: `backend/routers/tts.py`

**Step 1: Add imports and constants**

At the top of the file, add/update imports:

```python
import io
from datetime import datetime
from database import chat_db
```

Add after `DATABRICKS_LLM_MODEL`:

```python
# Volume configuration for TTS caching
DATABRICKS_VOLUME = os.environ.get('DATABRICKS_VOLUME', '')
```

**Step 2: Add helper functions**

Add after the `clean_text_for_tts` function:

```python
def is_caching_enabled(user: UserContext) -> bool:
    """Check if Volume caching is available"""
    return bool(DATABRICKS_VOLUME) and user.is_authenticated


def get_volume_path(user_id: str, thread_id: str, message_id: str) -> str:
    """Construct the Volume path for a TTS file"""
    return f"{DATABRICKS_VOLUME}tts_audio/{user_id}/{thread_id}/{message_id}.mp3"
```

**Step 3: Update the `text_to_speech` endpoint**

Replace the entire `text_to_speech` function with:

```python
@router.post("/speak")
async def text_to_speech(request: dict, user: UserContext = Depends(get_current_user)):
    """Convert text to speech using selected provider or fallback logic.
    Supports caching to Databricks Volumes when enabled.
    """
    try:
        raw_text = request.get("text", "").strip()
        if not raw_text:
            raise HTTPException(status_code=400, detail="Text is required")

        # Get caching parameters
        message_id = request.get("message_id")
        thread_id = request.get("thread_id")
        save_to_volume = request.get("save_to_volume", False)
        voice = request.get("voice", "af_nicole")
        preferred_provider = request.get("provider", "replicate").lower()

        # Log user context for debugging
        logger.info(f"TTS request from user: {user.user_id}")

        # Check if caching is possible
        can_cache = (
            is_caching_enabled(user) and
            message_id and
            thread_id and
            save_to_volume
        )

        # Try to fetch from cache if caching is enabled
        if can_cache:
            try:
                cached = chat_db.get_message_tts_cache(message_id, user.user_id)
                if cached and cached.get("voice") == voice:
                    # Cache hit - fetch from Volume
                    logger.info(f"TTS cache hit for message {message_id}")
                    workspace_client = user.get_workspace_client()
                    with workspace_client.files.download(cached["volume_path"]).contents as f:
                        audio_data = f.read()

                    def cached_audio_generator():
                        chunk_size = 8192
                        for i in range(0, len(audio_data), chunk_size):
                            yield audio_data[i:i + chunk_size]

                    return StreamingResponse(
                        cached_audio_generator(),
                        media_type="audio/mpeg",
                        headers={
                            "Cache-Control": "no-cache",
                            "Access-Control-Allow-Origin": "*",
                            "Content-Length": str(len(audio_data)),
                            "X-TTS-Provider": cached.get("provider", "cached"),
                            "X-TTS-Cache": "hit",
                        }
                    )
            except Exception as e:
                logger.warning(f"Cache fetch failed, regenerating: {e}")

        # Clean text using LLM for better TTS output
        print(f"===== TTS RAW TEXT (RECEIVED FROM CLIENT) =====")
        print(raw_text)
        print(f"=================================================")

        text = clean_text_for_tts(raw_text)

        print(f"===== TTS CLEANED TEXT (AFTER LLM CLEANING) =====")
        print(text)
        print(f"==================================================")

        audio_data = None
        provider_used = None
        error_messages = []

        # Try preferred provider first
        if preferred_provider == "replicate" and REPLICATE_API_TOKEN:
            try:
                print(f"Attempting TTS with Replicate for text: {text[:50]}...")
                print(f"Using Replicate voice: {voice}")
                output = replicate.run(
                    "jaaari/kokoro-82m:f559560eb822dc509045f3921a1921234918b91739db4bf3daab2169b71c7a13",
                    input={
                        "text": text,
                        "voice": voice,
                        "speed": 1.0
                    }
                )

                if output:
                    print(f"Replicate returned audio URL: {output}")
                    async with httpx.AsyncClient(timeout=30.0) as http_client:
                        audio_response = await http_client.get(str(output))
                        if audio_response.status_code == 200:
                            audio_data = audio_response.content
                            provider_used = "replicate"
                            print(f"Successfully downloaded audio from Replicate: {len(audio_data)} bytes")
                        else:
                            error_messages.append(f"Replicate URL fetch failed: {audio_response.status_code}")
                else:
                    error_messages.append("Replicate returned no output")
            except Exception as e:
                error_msg = f"Replicate TTS error: {str(e)}"
                print(error_msg)
                error_messages.append(error_msg)
        elif preferred_provider == "replicate":
            error_messages.append("Replicate API token not configured")

        # Try Deepgram if it's the preferred provider or as fallback
        if not audio_data and (preferred_provider == "deepgram" or not audio_data) and deepgram:
            try:
                if preferred_provider == "deepgram":
                    print(f"Using Deepgram (preferred) for text: {text[:50]}...")
                else:
                    print(f"Falling back to Deepgram for text: {text[:50]}...")

                deepgram_voice = voice if voice.startswith('aura-') else "aura-2-thalia-en"
                print(f"Using Deepgram voice: {deepgram_voice}")

                options = SpeakOptions(model=deepgram_voice)
                response = deepgram.speak.v("1").stream({"text": text}, options)

                if hasattr(response, 'content'):
                    audio_data = response.content
                elif hasattr(response, 'read'):
                    audio_data = response.read()
                elif hasattr(response, 'stream'):
                    chunks = []
                    for chunk in response.stream:
                        if chunk:
                            chunks.append(chunk)
                    audio_data = b''.join(chunks)
                else:
                    chunks = []
                    for chunk in response:
                        if chunk:
                            chunks.append(chunk)
                    audio_data = b''.join(chunks)

                if audio_data:
                    provider_used = "deepgram"
                    print(f"Successfully generated audio with Deepgram: {len(audio_data)} bytes")
                else:
                    error_messages.append("Deepgram returned no audio data")
            except Exception as e:
                error_msg = f"Deepgram TTS error: {str(e)}"
                print(error_msg)
                error_messages.append(error_msg)
        elif not audio_data:
            error_messages.append("Deepgram API not configured (fallback unavailable)")

        # If we have audio data, optionally cache and return it
        if audio_data:
            # Cache to Volume if enabled
            if can_cache:
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
                    logger.info(f"Cached TTS for message {message_id} at {volume_path}")
                except Exception as e:
                    logger.warning(f"Failed to cache TTS: {e}")
                    # Continue - still return the audio

            def audio_generator():
                chunk_size = 8192
                for i in range(0, len(audio_data), chunk_size):
                    yield audio_data[i:i + chunk_size]

            return StreamingResponse(
                audio_generator(),
                media_type="audio/mpeg",
                headers={
                    "Cache-Control": "no-cache",
                    "Access-Control-Allow-Origin": "*",
                    "Content-Length": str(len(audio_data)),
                    "X-TTS-Provider": provider_used,
                    "X-TTS-Cache": "miss" if can_cache else "disabled",
                }
            )
        else:
            error_detail = " | ".join(error_messages)
            raise HTTPException(
                status_code=503,
                detail=f"TTS failed with all providers: {error_detail}"
            )

    except HTTPException:
        raise
    except Exception as e:
        print(f"TTS error: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")
```

**Step 4: Verify syntax**

Run: `uv run python -c "from backend.routers.tts import router; print('OK')"`
Expected: OK

**Step 5: Commit**

```bash
git add backend/routers/tts.py
git commit -m "$(cat <<'EOF'
feat(backend): add TTS caching to Databricks Volumes

- Check cache on TTS request, fetch from Volume if cached
- Generate and cache if not cached
- Graceful fallback if caching fails

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2B: Add Settings UI Toggle for TTS Save to Volume

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`

**Step 1: Add the toggle widget method**

Add this method after `_buildEagerModeToggle()`:

```dart
Widget _buildTtsSaveToVolumeToggle() {
  final theme = Theme.of(context);
  final appColors = context.appColors;
  final saveToVolume = ref.watch(ttsSaveToVolumeProvider);

  return Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save TTS to Volume',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              saveToVolume
                  ? 'Audio files are cached for faster replay'
                  : 'Audio is generated fresh each time',
              style: theme.textTheme.bodySmall?.copyWith(
                color: appColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Switch(
        value: saveToVolume,
        onChanged: (value) {
          ref.read(ttsSaveToVolumeProvider.notifier).setSaveToVolume(value);
        },
        activeTrackColor: theme.colorScheme.primary,
      ),
    ],
  );
}
```

**Step 2: Add toggle to TTS settings section**

Find the Text-to-Speech card in the `build` method and add the toggle. Locate this section:

```dart
// Text-to-Speech Settings Section
_buildModernCard(
  context,
  icon: Icons.volume_up_outlined,
  title: 'Text-to-Speech',
  subtitle: 'Configure voice output settings',
  child: Column(
    children: [
      const SizedBox(height: 16),
      _buildTtsProviderDropdown(),
      const SizedBox(height: 16),
      _buildTtsVoiceDropdown(),
    ],
  ),
),
```

Update it to:

```dart
// Text-to-Speech Settings Section
_buildModernCard(
  context,
  icon: Icons.volume_up_outlined,
  title: 'Text-to-Speech',
  subtitle: 'Configure voice output settings',
  child: Column(
    children: [
      const SizedBox(height: 16),
      _buildTtsProviderDropdown(),
      const SizedBox(height: 16),
      _buildTtsVoiceDropdown(),
      const SizedBox(height: 16),
      _buildTtsSaveToVolumeToggle(),
    ],
  ),
),
```

**Step 3: Verify syntax**

Run: `flutter analyze lib/features/settings/presentation/settings_page.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/features/settings/presentation/settings_page.dart
git commit -m "$(cat <<'EOF'
feat(flutter): add TTS save to volume toggle in settings UI

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Group 3: Flutter Service + Chat Page Integration (PARALLEL)

### Task 3A: Update FastApiService.requestTts with Caching Parameters

**Files:**
- Modify: `lib/core/services/fastapi_service.dart`

**Step 1: Update `requestTts` method signature and body**

Find the `requestTts` method and replace it with:

```dart
/// Request text-to-speech audio from backend
/// Supports optional caching to Databricks Volumes when messageId, threadId, and saveToVolume are provided
static Future<http.Response> requestTts(
  String text, {
  String? provider,
  String? voice,
  String? messageId,
  String? threadId,
  bool saveToVolume = false,
}) async {
  try {
    final url = Uri.parse('$baseUrl/api/tts/speak');
    final requestBody = {
      'text': text,
      if (provider != null) 'provider': provider,
      if (voice != null) 'voice': voice,
      if (messageId != null) 'message_id': messageId,
      if (threadId != null) 'thread_id': threadId,
      'save_to_volume': saveToVolume,
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

**Step 2: Verify syntax**

Run: `flutter analyze lib/core/services/fastapi_service.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/core/services/fastapi_service.dart
git commit -m "$(cat <<'EOF'
feat(flutter): add caching params to requestTts method

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3B: Update Chat Page TTS Call with Caching Parameters

**Files:**
- Modify: `lib/features/chat/presentation/chat_home_page.dart`

**Step 1: Update the TTS request call**

Find the `_playTextToSpeech` method and locate this section (around line 1736):

```dart
// Get TTS settings
final ttsProvider = ref.read(ttsProviderProvider);
final ttsVoice = ref.read(ttsVoiceProvider);

// Call backend TTS API with cleaned text
final response = await FastApiService.requestTts(
  textToSend,  // Send raw text - backend will clean it using LLM
  provider: ttsProvider,
  voice: ttsVoice,
);
```

Replace it with:

```dart
// Get TTS settings
final ttsProvider = ref.read(ttsProviderProvider);
final ttsVoice = ref.read(ttsVoiceProvider);
final saveToVolume = ref.read(ttsSaveToVolumeProvider);

// Call backend TTS API with cleaned text and caching params
final response = await FastApiService.requestTts(
  textToSend,  // Send raw text - backend will clean it using LLM
  provider: ttsProvider,
  voice: ttsVoice,
  messageId: message.messageId,
  threadId: _currentThreadId,
  saveToVolume: saveToVolume,
);
```

**Step 2: Verify syntax**

Run: `flutter analyze lib/features/chat/presentation/chat_home_page.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/features/chat/presentation/chat_home_page.dart
git commit -m "$(cat <<'EOF'
feat(flutter): pass caching params to TTS requests

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Group 4: Port Changes to Deployment (PARALLEL)

### Task 4A: Port Database Changes to Deployment

**Files:**
- Modify: `deployment/database.py`

**Step 1: Copy the new methods**

Add the same `update_message_tts_cache` and `get_message_tts_cache` methods to the `ChatDatabase` class in `deployment/database.py`, identical to the changes made in Task 1A.

**Step 2: Verify syntax**

Run: `uv run python -c "import deployment.database; print('OK')"`
Expected: OK

**Step 3: Commit**

```bash
git add deployment/database.py
git commit -m "$(cat <<'EOF'
feat(deployment): port TTS cache database methods

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4B: Port TTS Router Changes to Deployment

**Files:**
- Modify: `deployment/routers/tts.py`

**Step 1: Copy the updated TTS router**

Apply the same changes made in Task 2A to `deployment/routers/tts.py`:
- Add imports (`io`, `datetime`, `chat_db`)
- Add `DATABRICKS_VOLUME` constant
- Add `is_caching_enabled` and `get_volume_path` helper functions
- Replace `text_to_speech` function with the caching-enabled version

**Step 2: Verify syntax**

Run: `uv run python -c "from deployment.routers.tts import router; print('OK')"`
Expected: OK

**Step 3: Commit**

```bash
git add deployment/routers/tts.py
git commit -m "$(cat <<'EOF'
feat(deployment): port TTS caching to deployment

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Group 5: Build and Test (SEQUENTIAL)

### Task 5: Build Flutter and Test Full Stack

**Files:**
- None (build/test only)

**Step 1: Build Flutter WASM**

Run: `flutter build web --wasm`
Expected: Build completes successfully

**Step 2: Start backend**

Run: `uv run python backend/app.py` (in background)
Expected: Server starts on port 8000

**Step 3: Test health endpoint**

Run: `curl http://localhost:8000/health`
Expected: `{"status":"healthy",...}`

**Step 4: Verify in browser**

Open: `http://localhost:8000`
- Navigate to Settings
- Verify "Save TTS to Volume" toggle appears under Text-to-Speech section
- Toggle is OFF by default
- Toggle persists across page refreshes

**Step 5: Final commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: complete TTS volume caching implementation

- Backend: database methods + TTS router caching logic
- Flutter: provider, settings UI, service, chat page integration
- Deployment: ported all changes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary: Parallel Execution Guide

| Group | Tasks | Can Run In Parallel |
|-------|-------|---------------------|
| 1 | 1A (backend DB), 1B (Flutter provider) | Yes |
| 2 | 2A (backend TTS router), 2B (Flutter settings UI) | Yes |
| 3 | 3A (FastApiService), 3B (chat page) | Yes |
| 4 | 4A (deployment DB), 4B (deployment TTS) | Yes |
| 5 | Build & test | Sequential (final) |

**Total: 9 tasks across 5 groups**
- Groups 1-4 have 2 parallel tasks each
- Group 5 is sequential verification
