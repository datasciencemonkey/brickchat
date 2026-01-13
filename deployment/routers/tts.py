from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import StreamingResponse
from deepgram import DeepgramClient, SpeakOptions
import replicate
import httpx
import os
import io
from datetime import datetime
from dotenv import load_dotenv
from functools import lru_cache
from openai import OpenAI
import logging
from auth import get_current_user, UserContext
from database import chat_db

load_dotenv()

router = APIRouter(prefix="/api/tts", tags=["text-to-speech"])

# Set up logging
logger = logging.getLogger(__name__)

# Get configuration from environment
DEEPGRAM_API_KEY = os.environ.get('DEEPGRAM_TOKEN', '')
REPLICATE_API_TOKEN = os.environ.get('REPLICATE_API_TOKEN', '')

# Databricks configuration for LLM text cleaning
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_LLM_MODEL = os.environ.get('DATABRICKS_LLM_MODEL', 'databricks-gemma-3-12b')

# Databricks Volume for TTS caching
DATABRICKS_VOLUME = "/Volumes/main/brickchat/tts_cache"

# Initialize clients
deepgram = DeepgramClient(DEEPGRAM_API_KEY) if DEEPGRAM_API_KEY else None

# Initialize Databricks client for text cleaning
databricks_client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
) if DATABRICKS_TOKEN else None


def _strip_think_tags(text: str) -> str:
    """
    Remove <think>...</think> reasoning blocks from text before TTS processing.
    This ensures reasoning content is never spoken aloud.
    """
    import re
    # Pattern to match <think>...</think> blocks (including multiline)
    think_pattern = re.compile(r'<think>.*?</think>\s*', re.DOTALL | re.IGNORECASE)
    cleaned = think_pattern.sub('', text)
    return cleaned.strip()


@lru_cache(maxsize=100)
def clean_text_for_tts(text: str) -> str:
    """
    Use LLM to clean text for TTS by removing footnotes, HTML tags, and formatting.
    Results are cached with LRU (Least Recently Used) strategy for efficiency.
    """
    # First strip any <think> reasoning blocks - these should never be spoken
    text = _strip_think_tags(text)

    if not text:
        logger.warning("No text remaining after stripping think tags")
        return ""

    if not databricks_client:
        logger.warning("Databricks client not configured, returning original text")
        return text

    try:
        prompt = """Act like a human who is editing this text to be optimized for listening by other humans.
Clean up and remove all footnotes, references, HTML tags, markdown formatting, and any reasoning/thinking process text.
Focus only on the actual informational content that should be spoken aloud.
Don't change the core subject or meaning, just make it natural for text-to-speech.
Return only the cleaned text without any explanation.

Text to clean:
{}""".format(text)

        # Call Databricks LLM with low temperature for consistent cleaning
        response = databricks_client.chat.completions.create(
            model=DATABRICKS_LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=2000,
            temperature=0.3
        )

        cleaned_text = response.choices[0].message.content.strip()

        # Log the cleaning for debugging
        logger.info(f"LLM cleaned text from {len(text)} to {len(cleaned_text)} characters")
        logger.debug(f"Original text (first 100 chars): {text[:100]}...")
        logger.debug(f"Cleaned text (first 100 chars): {cleaned_text[:100]}...")

        return cleaned_text

    except Exception as e:
        logger.error(f"LLM text cleaning failed: {str(e)}, using original text")
        return text


def is_caching_enabled(user: UserContext) -> bool:
    """Check if TTS caching is available (user is authenticated with access token)."""
    return user.is_authenticated and user.access_token is not None


def get_volume_path(user_id: str, message_id: str, voice: str) -> str:
    """Generate the Volume path for a cached TTS file."""
    return f"{DATABRICKS_VOLUME}/{user_id}/{message_id}_{voice}.mp3"


async def fetch_from_volume(user: UserContext, volume_path: str) -> bytes | None:
    """Fetch audio from Databricks Volume if it exists."""
    if not user.access_token:
        return None

    try:
        workspace_client = user.get_workspace_client()
        # Use Files API to read from Volume
        with workspace_client.files.download(volume_path).contents as f:
            return f.read()
    except Exception as e:
        logger.debug(f"Volume fetch failed (may not exist): {e}")
        return None


async def save_to_volume(user: UserContext, volume_path: str, audio_data: bytes) -> bool:
    """Save audio to Databricks Volume."""
    if not user.access_token:
        return False

    try:
        workspace_client = user.get_workspace_client()
        # Use Files API to write to Volume
        workspace_client.files.upload(volume_path, io.BytesIO(audio_data), overwrite=True)
        logger.info(f"Saved TTS audio to Volume: {volume_path}")
        return True
    except Exception as e:
        logger.error(f"Failed to save to Volume: {e}")
        return False


@router.post("/speak")
async def text_to_speech(request: dict, user: UserContext = Depends(get_current_user)):
    """Convert text to speech using selected provider or fallback logic.
    Supports caching to Databricks Volumes when save_to_volume is enabled.
    """
    try:
        raw_text = request.get("text", "").strip()
        if not raw_text:
            raise HTTPException(status_code=400, detail="Text is required")

        # Log user context for debugging
        logger.info(f"TTS request from user: {user.user_id}")

        # Get caching parameters from request
        message_id = request.get("message_id")
        save_to_volume = request.get("save_to_volume", False)

        # Get provider preference from request (defaults to replicate)
        preferred_provider = request.get("provider", "replicate").lower()
        voice = request.get("voice", "af_nicole")  # Default voice

        audio_data = None
        provider_used = None
        error_messages = []
        from_cache = False

        # Check cache if message_id is provided and caching is enabled
        if message_id and save_to_volume and is_caching_enabled(user):
            # Check database for cached TTS info
            cache_info = chat_db.get_message_tts_cache(message_id, user.user_id) if chat_db else None

            if cache_info and cache_info.get("voice") == voice:
                # Same voice, try to fetch from Volume
                volume_path = cache_info.get("volume_path")
                if volume_path:
                    cached_audio = await fetch_from_volume(user, volume_path)
                    if cached_audio:
                        audio_data = cached_audio
                        from_cache = True
                        provider_used = "cache"
                        logger.info(f"Serving TTS from cache: {volume_path}")

        # If not from cache, generate fresh audio
        if not audio_data:
            # Clean text using LLM for better TTS output
            print(f"===== TTS RAW TEXT (RECEIVED FROM CLIENT) =====")
            print(raw_text)
            print(f"=================================================")

            text = clean_text_for_tts(raw_text)

            print(f"===== TTS CLEANED TEXT (AFTER LLM CLEANING) =====")
            print(text)
            print(f"==================================================")

            # Try preferred provider first
            if preferred_provider == "replicate" and REPLICATE_API_TOKEN:
                try:
                    print(f"Attempting TTS with Replicate for text: {text[:50]}...")

                    # Run Replicate TTS model with selected voice
                    print(f"Using Replicate voice: {voice}")
                    output = replicate.run(
                        "jaaari/kokoro-82m:f559560eb822dc509045f3921a1921234918b91739db4bf3daab2169b71c7a13",
                        input={
                            "text": text,
                            "voice": voice,
                            "speed": 1.0
                        }
                    )

                    # Output is a URL to the audio file
                    if output:
                        print(f"Replicate returned audio URL: {output}")

                        # Download the audio from the URL
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

                    # Use the voice from request if it's a Deepgram voice, otherwise use default
                    deepgram_voice = voice if voice.startswith('aura-') else "aura-2-thalia-en"
                    print(f"Using Deepgram voice: {deepgram_voice}")

                    # Configure Deepgram options with selected voice
                    options = SpeakOptions(
                        model=deepgram_voice,
                    )

                    # Generate speech and get the response object
                    response = deepgram.speak.v("1").stream(
                        {"text": text},
                        options,
                    )

                    # Extract audio data from response
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

            # Cache to volume if newly generated and caching is enabled
            if audio_data and not from_cache and message_id and save_to_volume and is_caching_enabled(user):
                volume_path = get_volume_path(user.user_id, message_id, voice)
                saved = await save_to_volume(user, volume_path, audio_data)
                if saved and chat_db:
                    # Update database with cache info
                    cache_info = {
                        "voice": voice,
                        "provider": provider_used,
                        "volume_path": volume_path,
                        "cached_at": datetime.utcnow().isoformat()
                    }
                    chat_db.update_message_tts_cache(message_id, cache_info)
                    logger.info(f"Cached TTS for message {message_id}")

        # If we have audio data, return it
        if audio_data:
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
                    "X-TTS-Provider": provider_used,  # Include provider info
                }
            )
        else:
            # Both providers failed
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
