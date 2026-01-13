# Streaming TTS Pipeline Design

**Date:** 2026-01-13
**Status:** Implemented

## Overview

A streaming TTS pipeline that reduces time-to-first-audio by chaining LLM text cleaning and Deepgram TTS in a streaming fashion. This feature only applies when **Eager Mode is ON**.

## Problem Statement

Currently, when eager mode triggers TTS after a chat response:
1. Wait for full text → Send to LLM for cleaning → Wait for full cleaned text
2. Send cleaned text to TTS → Wait for full audio generation
3. Play audio

Users experience significant delay before hearing any audio, especially for long responses.

## Solution

Stream the entire pipeline:
1. As soon as chat streaming completes, start LLM cleaning with streaming output
2. As cleaned text chunks arrive, detect sentence boundaries and feed to Deepgram streaming TTS
3. As audio chunks arrive, play them immediately using Web Audio API

## Behavior by Mode

| Mode | On Stream Complete | On Play Click |
|------|-------------------|---------------|
| **Eager ON** | Start LLM cleaning → Deepgram TTS → Auto-play | N/A (already playing) |
| **Eager OFF** | Nothing | Full audio generation, wait, then play (unchanged) |

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐     ┌──────────────┐
│ Chat streaming  │────▶│ LLM cleaning         │────▶│ Deepgram        │────▶│ Browser      │
│ completes       │     │ (streaming output)   │     │ streaming TTS   │     │ audio player │
└─────────────────┘     └──────────────────────┘     └─────────────────┘     └──────────────┘
```

### Data Flow (Eager Mode Only)

```
Chat stream done ──▶ /api/tts/speak-stream ──▶ Audio chunks ──▶ Play immediately
                           │
                           ├── LLM cleaning (streaming)
                           │         │
                           │         ▼
                           └── Deepgram TTS (streaming)
```

## Backend Changes

### New Endpoint: `POST /api/tts/speak-stream`

**Request:**
```json
{
  "text": "raw message text with markdown, footnotes, etc.",
  "voice": "aura-2-thalia-en"
}
```

**Response:** Server-Sent Events (SSE)

```
data: {"type": "audio", "chunk": "<base64 encoded audio bytes>"}
data: {"type": "audio", "chunk": "<base64 encoded audio bytes>"}
...
data: {"type": "done"}
```

**Error case:**
```
data: {"type": "error", "message": "TTS generation failed: ..."}
```

### Pipeline Implementation

```python
@router.post("/speak-stream")
async def text_to_speech_stream(request: dict):
    raw_text = request.get("text", "").strip()
    voice = request.get("voice", "aura-2-thalia-en")

    async def generate():
        # 1. Strip <think> tags (fast, regex)
        text = _strip_think_tags(raw_text)

        # 2. Stream to Databricks LLM for cleaning
        sentence_buffer = ""
        async for cleaned_chunk in stream_clean_text(text):
            sentence_buffer += cleaned_chunk

            # 3. Detect sentence boundaries
            while has_complete_sentence(sentence_buffer):
                sentence, sentence_buffer = extract_sentence(sentence_buffer)

                # 4. Send sentence to Deepgram streaming TTS
                async for audio_chunk in deepgram_stream_tts(sentence, voice):
                    # 5. Yield audio chunks as SSE
                    yield f"data: {json.dumps({'type': 'audio', 'chunk': base64.b64encode(audio_chunk).decode()})}\n\n"

        # Handle remaining text in buffer
        if sentence_buffer.strip():
            async for audio_chunk in deepgram_stream_tts(sentence_buffer, voice):
                yield f"data: {json.dumps({'type': 'audio', 'chunk': base64.b64encode(audio_chunk).decode()})}\n\n"

        yield f"data: {json.dumps({'type': 'done'})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")
```

### Helper Functions

**Sentence boundary detection:**
```python
def has_complete_sentence(text: str) -> bool:
    """Check if buffer contains a complete sentence."""
    # Look for sentence-ending punctuation followed by space or newline
    pattern = r'[.!?]\s+'
    return bool(re.search(pattern, text))

def extract_sentence(text: str) -> tuple[str, str]:
    """Extract first complete sentence from buffer."""
    match = re.search(r'^(.*?[.!?])\s+', text)
    if match:
        return match.group(1), text[match.end():]
    return text, ""
```

**Streaming LLM cleaning:**
```python
async def stream_clean_text(text: str):
    """Stream text through Databricks LLM for cleaning."""
    prompt = """Clean this text for TTS. Remove footnotes, references, HTML tags, markdown.
Return only the cleaned text, nothing else.

Text: {}""".format(text)

    response = databricks_client.chat.completions.create(
        model=DATABRICKS_LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=2000,
        temperature=0.3,
        stream=True  # Enable streaming
    )

    for chunk in response:
        if chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content
```

**Deepgram streaming TTS:**
```python
async def deepgram_stream_tts(text: str, voice: str):
    """Stream audio from Deepgram TTS."""
    options = SpeakOptions(model=voice)

    # Use Deepgram's streaming response
    response = deepgram.speak.v("1").stream({"text": text}, options)

    # Yield chunks as they arrive
    if hasattr(response, 'stream'):
        for chunk in response.stream:
            if chunk:
                yield chunk
    elif hasattr(response, 'iter_bytes'):
        for chunk in response.iter_bytes():
            if chunk:
                yield chunk
    else:
        # Fallback: yield entire content
        if hasattr(response, 'content'):
            yield response.content
```

## Frontend Changes

### New Service Method in `fastapi_service.dart`

```dart
/// Stream TTS audio chunks via SSE (for eager mode)
static Stream<List<int>> streamTts(String text, {String? voice}) async* {
  final url = Uri.parse('$baseUrl/api/tts/speak-stream');

  final request = http.Request('POST', url);
  request.headers['Content-Type'] = 'application/json';
  request.body = json.encode({
    'text': text,
    if (voice != null) 'voice': voice,
  });

  final streamedResponse = await request.send();

  if (streamedResponse.statusCode == 200) {
    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = json.decode(line.substring(6));

          if (data['type'] == 'audio') {
            // Decode base64 audio chunk
            yield base64Decode(data['chunk']);
          } else if (data['type'] == 'error') {
            throw Exception(data['message']);
          } else if (data['type'] == 'done') {
            return;
          }
        }
      }
    }
  } else {
    throw Exception('Streaming TTS failed: ${streamedResponse.statusCode}');
  }
}
```

### Web Audio API Streaming Playback

```dart
// In chat_home_page.dart

AudioContext? _audioContext;
List<AudioBuffer> _audioQueue = [];
double _nextStartTime = 0;
bool _isStreamingAudio = false;

Future<void> _playStreamingTts(ChatMessage message) async {
  if (!mounted) return;

  setState(() {
    _isStreamingAudio = true;
    _currentPlayingMessageId = message.id;
  });

  // Initialize Web Audio API context
  _audioContext = AudioContext();
  _nextStartTime = _audioContext!.currentTime;

  final ttsVoice = ref.read(ttsVoiceProvider);

  try {
    await for (final audioChunk in FastApiService.streamTts(
      message.text,
      voice: ttsVoice,
    )) {
      if (!mounted || !_isStreamingAudio) break;

      // Decode audio chunk
      final audioBuffer = await _audioContext!.decodeAudioData(audioChunk);

      // Schedule playback
      final source = _audioContext!.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(_audioContext!.destination);
      source.start(_nextStartTime);

      // Update next start time for seamless playback
      _nextStartTime += audioBuffer.duration;
    }
  } catch (e) {
    // Handle error, maybe fall back to non-streaming TTS
  } finally {
    setState(() {
      _isStreamingAudio = false;
    });
  }
}
```

### Integration in `_sendMessage()`

Update the eager mode auto-trigger section:

```dart
// After streaming completes (around line 432-448)
if (mounted) {
  final messageIndex = _messages.indexWhere((msg) => msg.id == assistantMessageId);
  if (messageIndex != -1) {
    _messages[messageIndex].isStreaming = false;
    setState(() {});

    // Auto-trigger TTS if eager mode is enabled
    final eagerMode = ref.read(eagerModeProvider);
    if (eagerMode && responseBuffer.isNotEmpty) {
      // Use streaming TTS for eager mode
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && messageIndex != -1) {
          _playStreamingTts(_messages[messageIndex]);  // NEW: Use streaming version
        }
      });
    }
  }
}
```

## Implementation Details

### Sentence Boundary Detection

Buffer LLM output and emit on:
- `. ` (period + space)
- `? ` (question mark + space)
- `! ` (exclamation + space)
- `.\n` (period + newline)

Minimum sentence length: 10 characters (avoid splitting abbreviations like "Dr. Smith")

### Audio Format

- Deepgram returns MP3 audio by default
- Each sentence generates a separate audio segment
- Web Audio API decodes and schedules segments for seamless playback

### Error Handling

1. **LLM cleaning fails:** Fall back to regex-based cleaning, continue pipeline
2. **Deepgram fails mid-stream:** Stop streaming, show error to user
3. **Network interruption:** Gracefully stop playback, allow retry

### Performance Considerations

1. **Sentence buffer size:** Keep sentences reasonable length (not too short to avoid choppy audio)
2. **Parallel processing:** Could potentially start TTS for sentence N while LLM is still generating sentence N+1
3. **Memory:** Audio chunks are played and discarded, not cached (for streaming mode)

## Files to Modify

### Backend
- `backend/routers/tts.py` - Add `/speak-stream` endpoint and helper functions

### Frontend
- `lib/core/services/fastapi_service.dart` - Add `streamTts()` method
- `lib/features/chat/presentation/chat_home_page.dart` - Add streaming audio playback, update eager mode trigger

## Testing Plan

1. **Unit tests:** Sentence boundary detection logic
2. **Integration test:** Full pipeline with mock LLM and TTS responses
3. **Manual testing:**
   - Enable eager mode, send message, verify audio starts quickly
   - Disable eager mode, verify existing behavior unchanged
   - Test with short and long responses
   - Test error scenarios (network failure mid-stream)

## Future Enhancements

1. **Visual indicator:** Show which sentence is currently being spoken
2. **Playback controls:** Pause/resume streaming audio
3. **Caching:** Option to cache streamed audio for replay
4. **Voice selection:** Per-message voice selection for streaming mode
