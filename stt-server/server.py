"""OpenAI-compatible STT server wrapping whisper.cpp (CPU)."""

import logging
import os
import subprocess
import tempfile

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ROOT = os.environ.get("DEVENV_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", os.path.join(PROJECT_ROOT, "models", "ggml-base.en.bin"))
WHISPER_BIN = "whisper-cpp"

app = FastAPI(title="Whisper STT Server", version="1.0.0")


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form("whisper-1"),
    language: str = Form("en"),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    if not os.path.isfile(MODEL_PATH):
        raise HTTPException(
            status_code=503,
            detail=f"Model not found at {MODEL_PATH}. Run 'download-models' first.",
        )

    # Write uploaded audio to a temp file (whisper-cpp needs a file path)
    suffix = os.path.splitext(file.filename or ".wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    # Convert to 16kHz mono WAV (whisper-cpp requirement)
    wav_path = tmp_path + ".wav"
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", tmp_path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav_path],
            capture_output=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        os.unlink(tmp_path)
        raise HTTPException(status_code=400, detail=f"Failed to convert audio: {e.stderr.decode()}")

    # Run whisper-cpp
    try:
        result = subprocess.run(
            [
                WHISPER_BIN,
                "--model", MODEL_PATH,
                "--file", wav_path,
                "--language", language,
                "--no-timestamps",
                "--output-txt",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail=f"'{WHISPER_BIN}' binary not found. Is whisper-cpp installed?")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Transcription timed out.")
    finally:
        os.unlink(tmp_path)

    # whisper-cpp --output-txt writes to <input>.txt
    txt_path = wav_path + ".txt"
    if os.path.isfile(txt_path):
        text = open(txt_path).read().strip()
        os.unlink(txt_path)
    else:
        # Fallback: parse from stdout
        text = result.stdout.strip()
        # whisper-cpp stdout has lines like "[00:00:00.000 --> 00:00:05.000]  Hello world"
        lines = []
        for line in text.splitlines():
            if "]" in line:
                lines.append(line.split("]", 1)[1].strip())
            elif line.strip():
                lines.append(line.strip())
        text = " ".join(lines)

    os.unlink(wav_path)

    if response_format == "text":
        return text

    return JSONResponse(content={"text": text})


@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [{"id": "whisper-1", "object": "model", "owned_by": "local"}],
    }


@app.get("/health")
def health():
    return {"status": "ok", "model_exists": os.path.isfile(MODEL_PATH)}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
