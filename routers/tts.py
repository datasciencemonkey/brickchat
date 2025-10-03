from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from deepgram import DeepgramClient, SpeakOptions
import replicate
import httpx
import os
from dotenv import load_dotenv
load_dotenv()

router = APIRouter(prefix="/api/tts", tags=["text-to-speech"])

# Get configuration from environment
DEEPGRAM_API_KEY = os.environ.get('DEEPGRAM_TOKEN', '')
REPLICATE_API_TOKEN = os.environ.get('REPLICATE_API_TOKEN', '')

# Initialize clients
deepgram = DeepgramClient(DEEPGRAM_API_KEY) if DEEPGRAM_API_KEY else None


@router.post("/speak")
async def text_to_speech(request: dict):
    """Convert text to speech using selected provider or fallback logic"""
    try:
        text = request.get("text", "").strip()
        if not text:
            raise HTTPException(status_code=400, detail="Text is required")

        # Get provider preference from request (defaults to replicate)
        preferred_provider = request.get("provider", "replicate").lower()
        voice = request.get("voice", "af_nicole")  # Default voice

        audio_data = None
        provider_used = None
        error_messages = []

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
