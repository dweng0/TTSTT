# TTSTT 🐍

> *"tsssst"* — local CPU-based speech servers with OpenAI-compatible APIs

TTSTT runs speech-to-text and text-to-speech on your CPU, no GPU required. Both services expose OpenAI-compatible endpoints, so any client that talks to the OpenAI audio API works out of the box.

## What's inside

| Service | Engine | Port | Endpoint |
|---------|--------|------|----------|
| **STT** | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (base.en) | 8000 | `POST /v1/audio/transcriptions` |
| **TTS** | [Piper](https://github.com/rhasspy/piper) (lessac-medium) | 8001 | `POST /v1/audio/speech` |

Both servers also expose `/health`, `/v1/models`, and the TTS server has `/v1/voices`.

## Quick start

Requires [devenv](https://devenv.sh).

```bash
cd TTSTT
devenv shell          # enter the dev environment
download-models       # fetch whisper + piper models (~200MB)
devenv up             # start both servers
```

## Usage

**Transcribe audio (STT):**
```bash
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F file=@recording.wav \
  -F model=whisper-1
```

**Generate speech (TTS):**
```bash
curl -X POST http://localhost:8001/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello from TTSTT", "voice": "alloy"}' \
  --output speech.wav
```

**With the OpenAI Python client:**
```python
from openai import OpenAI

# STT
stt = OpenAI(base_url="http://localhost:8000/v1", api_key="unused")
transcript = stt.audio.transcriptions.create(
    model="whisper-1",
    file=open("recording.wav", "rb"),
)
print(transcript.text)

# TTS
tts = OpenAI(base_url="http://localhost:8001/v1", api_key="unused")
response = tts.audio.speech.create(
    model="piper",
    voice="alloy",
    input="Hello from TTSTT",
)
response.stream_to_file("speech.wav")
```

## TTS voices

The API accepts standard OpenAI voice names (`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`) for compatibility. The bundled piper model (lessac-medium) has a single high-quality English speaker, so all names map to the same voice.

Swap in a different [piper voice](https://rhasspy.github.io/piper-samples/) by downloading the `.onnx` + `.onnx.json` files into `models/` and updating the model path in `tts-server/server.py`.

## Supported audio formats

TTS output: `wav`, `mp3`, `flac`, `opus`, `aac`, `pcm`
STT input: anything ffmpeg can decode
