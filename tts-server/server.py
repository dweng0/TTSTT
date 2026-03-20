"""OpenAI-compatible TTS server wrapping piper-tts (CPU)."""

import io
import logging
import os
import subprocess
import tempfile
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ROOT = os.environ.get("DEVENV_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL_PATH = os.environ.get("PIPER_MODEL_PATH", os.path.join(PROJECT_ROOT, "models", "en_US-lessac-medium.onnx"))
PIPER_BIN = "piper"

# Piper outputs raw 16-bit PCM at the model's sample rate (usually 22050 Hz)
PIPER_SAMPLE_RATE = 22050

# Map OpenAI voice names to piper speaker IDs (lessac-medium has 1 speaker, id=0)
# Users can still pass these names for API compatibility
VOICE_MAP = {
    "alloy": 0,
    "echo": 0,
    "fable": 0,
    "onyx": 0,
    "nova": 0,
    "shimmer": 0,
}

MIME_TYPES = {
    "wav": "audio/wav",
    "mp3": "audio/mpeg",
    "flac": "audio/flac",
    "opus": "audio/opus",
    "aac": "audio/aac",
    "pcm": "audio/pcm",
}

app = FastAPI(title="Piper TTS Server", version="1.0.0")


class SpeechRequest(BaseModel):
    model: str = "piper"
    input: str
    voice: str = "alloy"
    response_format: Optional[str] = "wav"
    speed: Optional[float] = 1.0


@app.post("/v1/audio/speech")
def create_speech(request: SpeechRequest):
    if not request.input.strip():
        raise HTTPException(status_code=400, detail="'input' must not be empty.")

    if not os.path.isfile(MODEL_PATH):
        raise HTTPException(
            status_code=503,
            detail=f"Model not found at {MODEL_PATH}. Run 'download-models' first.",
        )

    fmt = (request.response_format or "wav").lower()
    if fmt not in MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format '{fmt}'. Choose from: {list(MIME_TYPES)}.",
        )

    speaker = VOICE_MAP.get(request.voice.lower(), 0)
    length_scale = 1.0 / (request.speed or 1.0)

    logger.info(f"Synthesising | voice={request.voice} speaker={speaker} fmt={fmt} chars={len(request.input)}")

    # Generate raw WAV with piper
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name

    try:
        result = subprocess.run(
            [
                PIPER_BIN,
                "--model", MODEL_PATH,
                "--speaker", str(speaker),
                "--length-scale", str(length_scale),
                "--output_file", wav_path,
            ],
            input=request.input,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=f"Piper error: {result.stderr}")

        if fmt == "wav":
            with open(wav_path, "rb") as f:
                audio_bytes = f.read()
        elif fmt == "pcm":
            # Strip WAV header, return raw PCM
            with open(wav_path, "rb") as f:
                data = f.read()
            # WAV data starts after the header (44 bytes for standard WAV)
            audio_bytes = data[44:]
        else:
            # Convert via ffmpeg for mp3/flac/opus/aac
            out_path = wav_path + f".{fmt}"
            subprocess.run(
                ["ffmpeg", "-y", "-i", wav_path, out_path],
                capture_output=True,
                check=True,
            )
            with open(out_path, "rb") as f:
                audio_bytes = f.read()
            os.unlink(out_path)
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail=f"'{PIPER_BIN}' binary not found. Is piper-tts installed?")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Speech synthesis timed out.")
    finally:
        if os.path.isfile(wav_path):
            os.unlink(wav_path)

    return Response(content=audio_bytes, media_type=MIME_TYPES[fmt])


@app.get("/v1/voices")
def list_voices():
    return {
        "voices": [
            {"id": name, "speaker_id": sid}
            for name, sid in VOICE_MAP.items()
        ]
    }


@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [{"id": "piper", "object": "model", "owned_by": "local"}],
    }


@app.get("/health")
def health():
    return {"status": "ok", "model_exists": os.path.isfile(MODEL_PATH)}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
