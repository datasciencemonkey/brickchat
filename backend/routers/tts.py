from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import StreamingResponse
from deepgram import DeepgramClient, SpeakOptions
import os
import re
import json
import base64
import asyncio
from dotenv import load_dotenv
from functools import lru_cache
from typing import AsyncGenerator
from openai import OpenAI
import logging
from auth import get_current_user, UserContext

load_dotenv()

router = APIRouter(prefix="/api/tts", tags=["text-to-speech"])

# Set up logging
logger = logging.getLogger(__name__)

# Get configuration from environment
DEEPGRAM_API_KEY = os.environ.get('DEEPGRAM_TOKEN', '')

# Databricks configuration for LLM text cleaning
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN', '')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', '')
DATABRICKS_LLM_MODEL = os.environ.get('DATABRICKS_LLM_MODEL', 'databricks-gemma-3-12b')

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


# =============================================================================
# Streaming TTS Pipeline
# =============================================================================

# Minimum sentence length to avoid splitting abbreviations like "Dr. Smith"
MIN_SENTENCE_LENGTH = 10


def has_complete_sentence(text: str) -> bool:
    """Check if buffer contains a complete sentence."""
    # Look for sentence-ending punctuation followed by space or newline
    # Must have minimum length to avoid splitting on abbreviations
    pattern = r'[.!?]\s+'
    match = re.search(pattern, text)
    if match and match.start() >= MIN_SENTENCE_LENGTH:
        return True
    return False


def extract_sentence(text: str) -> tuple[str, str]:
    """Extract first complete sentence from buffer."""
    # Find sentence boundary (. ! ?) followed by whitespace
    match = re.search(r'^(.*?[.!?])\s+', text, re.DOTALL)
    if match:
        sentence = match.group(1).strip()
        remaining = text[match.end():].strip()
        return sentence, remaining
    return text, ""


async def stream_clean_text(text: str) -> AsyncGenerator[str, None]:
    """Stream text through Databricks LLM for cleaning."""
    if not databricks_client:
        logger.warning("Databricks client not configured, returning original text")
        yield text
        return

    prompt = """Act like a human who is editing this text to be optimized for listening by other humans.
Clean up and remove all footnotes, references, HTML tags, markdown formatting, and any reasoning/thinking process text.
Focus only on the actual informational content that should be spoken aloud.
Don't change the core subject or meaning, just make it natural for text-to-speech.
Return only the cleaned text without any explanation.

Text to clean:
{}""".format(text)

    try:
        response = databricks_client.chat.completions.create(
            model=DATABRICKS_LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=2000,
            temperature=0.3,
            stream=True  # Enable streaming
        )

        for chunk in response:
            if chunk.choices and chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

    except Exception as e:
        logger.error(f"Streaming LLM cleaning failed: {e}, returning original text")
        yield text


async def deepgram_stream_tts(text: str, voice: str) -> AsyncGenerator[bytes, None]:
    """Stream audio from Deepgram TTS for a sentence."""
    if not deepgram:
        logger.error("Deepgram client not configured")
        return

    try:
        options = SpeakOptions(model=voice)

        # Use Deepgram's newer REST API (speak.rest.v('1').stream_memory)
        response = deepgram.speak.rest.v("1").stream_memory(
            {"text": text},
            options,
        )

        # Read the audio stream and yield it
        if hasattr(response, 'stream') and response.stream:
            audio_data = response.stream.read()
            if audio_data:
                # Yield in chunks for better streaming
                chunk_size = 8192  # 8KB chunks
                for i in range(0, len(audio_data), chunk_size):
                    yield audio_data[i:i + chunk_size]
        else:
            logger.warning("Deepgram response has no stream attribute")

    except Exception as e:
        logger.error(f"Deepgram streaming TTS error: {e}")
        raise


@router.post("/speak-stream")
async def text_to_speech_stream(request: dict, user: UserContext = Depends(get_current_user)):
    """
    Streaming TTS endpoint for eager mode.
    Streams text through LLM cleaning -> Deepgram TTS -> Audio chunks via SSE.
    """
    raw_text = request.get("text", "").strip()
    if not raw_text:
        raise HTTPException(status_code=400, detail="Text is required")

    voice = request.get("voice", "aura-2-thalia-en")

    # Ensure it's a Deepgram voice for streaming
    if not voice.startswith('aura-'):
        voice = "aura-2-thalia-en"

    logger.info(f"Streaming TTS request from user: {user.user_id}, text length: {len(raw_text)}")

    async def generate():
        try:
            # 1. Strip <think> tags (fast, regex)
            text = _strip_think_tags(raw_text)

            if not text:
                yield f"data: {json.dumps({'type': 'error', 'message': 'No text after cleaning'})}\n\n"
                return

            logger.info(f"Starting streaming TTS pipeline for {len(text)} chars")

            # 2. Stream through LLM for cleaning and buffer for sentence detection
            sentence_buffer = ""
            sentences_processed = 0

            async for cleaned_chunk in stream_clean_text(text):
                sentence_buffer += cleaned_chunk

                # 3. Detect sentence boundaries and process complete sentences
                while has_complete_sentence(sentence_buffer):
                    sentence, sentence_buffer = extract_sentence(sentence_buffer)

                    if sentence.strip():
                        sentences_processed += 1
                        logger.debug(f"Processing sentence {sentences_processed}: {sentence[:50]}...")

                        # 4. Send sentence to Deepgram streaming TTS
                        try:
                            async for audio_chunk in deepgram_stream_tts(sentence, voice):
                                # 5. Yield audio chunks as SSE
                                encoded = base64.b64encode(audio_chunk).decode('utf-8')
                                yield f"data: {json.dumps({'type': 'audio', 'chunk': encoded})}\n\n"
                                # Small delay to allow client to process
                                await asyncio.sleep(0.01)
                        except Exception as e:
                            logger.error(f"Error processing sentence {sentences_processed}: {e}")
                            # Continue with next sentence instead of failing completely
                            continue

            # Handle remaining text in buffer (last sentence without trailing whitespace)
            if sentence_buffer.strip():
                sentences_processed += 1
                logger.debug(f"Processing final sentence {sentences_processed}: {sentence_buffer[:50]}...")

                try:
                    async for audio_chunk in deepgram_stream_tts(sentence_buffer.strip(), voice):
                        encoded = base64.b64encode(audio_chunk).decode('utf-8')
                        yield f"data: {json.dumps({'type': 'audio', 'chunk': encoded})}\n\n"
                        await asyncio.sleep(0.01)
                except Exception as e:
                    logger.error(f"Error processing final sentence: {e}")

            logger.info(f"Streaming TTS complete: {sentences_processed} sentences processed")
            yield f"data: {json.dumps({'type': 'done', 'sentences': sentences_processed})}\n\n"

        except Exception as e:
            logger.error(f"Streaming TTS pipeline error: {e}")
            import traceback
            traceback.print_exc()
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "Access-Control-Allow-Origin": "*",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
        }
    )
