# AIT — AI Trifecta

> Local AI services with OpenAI-compatible APIs — speech-to-text, text-to-speech, and LLM inference in one stack.

AIT gives you three AI services behind standard OpenAI-compatible endpoints. STT and TTS run on CPU. The LLM service (ollama) auto-detects NVIDIA GPUs and offloads to VRAM when available.

## Services

| Service | Engine | Port | Endpoint |
|---------|--------|------|----------|
| **STT** | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | 8000 | `POST /v1/audio/transcriptions` |
| **TTS** | [Piper](https://github.com/rhasspy/piper) | 8001 | `POST /v1/audio/speech` |
| **LLM** | [Ollama](https://ollama.com) | 11434 | `POST /v1/chat/completions` |

All services expose `/health` and `/v1/models`. TTS also has `/v1/voices`.

## Quick start

Requires [devenv](https://devenv.sh).

```bash
devenv shell            # enter the dev environment
download-models         # interactive picker for STT/TTS models
ollama pull llama3.1:8b # pull an LLM of your choice
devenv up               # start all three services
```

## Pulling LLM models

Ollama manages LLM models separately. Pull whatever fits your hardware:

```bash
# Small / CPU-friendly
ollama pull phi3:mini
ollama pull gemma2:2b

# Medium / 8-16GB VRAM
ollama pull llama3.1:8b
ollama pull mistral

# Large / 24-32GB+ VRAM
ollama pull llama3.1:70b-instruct-q4_K_M
ollama pull deepseek-coder-v2:33b

# List what you have
ollama list
```

Browse all available models at [ollama.com/library](https://ollama.com/library).

## Usage

### Chat with an LLM

```bash
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Transcribe audio (STT)

```bash
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F file=@recording.wav \
  -F model=whisper-1
```

### Generate speech (TTS)

```bash
curl -X POST http://localhost:8001/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello from AIT", "voice": "alloy"}' \
  --output speech.wav
```

### OpenAI Python client

All three services work with the standard OpenAI client — just point `base_url` at the right port:

```python
from openai import OpenAI

# LLM
llm = OpenAI(base_url="http://localhost:11434/v1", api_key="unused")
response = llm.chat.completions.create(
    model="llama3.1:8b",
    messages=[{"role": "user", "content": "Explain quantum computing in one sentence."}],
)
print(response.choices[0].message.content)

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
    input="Hello from AIT",
)
response.stream_to_file("speech.wav")
```

## STT/TTS models

`download-models` presents an interactive menu for each:

**Whisper (STT):**

| Option | Model | Size | Notes |
|--------|-------|------|-------|
| 1 | tiny.en | ~75MB | Fastest, lower accuracy |
| 2 | base.en | ~142MB | Good balance for English |
| 3 | small.en | ~466MB | Higher accuracy |
| 4 | medium.en | ~1.5GB | High accuracy |
| 5 | large-v3 | ~3.1GB | Best accuracy, multilingual |
| 6 | large-v3-turbo | ~1.6GB | Near-large accuracy, faster |

**Piper (TTS):**

| Option | Voice | Size | Notes |
|--------|-------|------|-------|
| 1 | lessac (low) | ~15MB | Fast, lower quality |
| 2 | lessac (medium) | ~50MB | Good balance |
| 3 | lessac (high) | ~100MB | Best quality |
| 4 | amy (medium) | ~50MB | Different US English speaker |
| 5 | alba (medium) | ~50MB | Scottish English speaker |

Run `download-models` again at any time to switch models. Browse more piper voices at [piper-samples](https://rhasspy.github.io/piper-samples/).

The TTS API accepts standard OpenAI voice names (`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`) for compatibility — they all map to the selected piper voice.

## Supported formats

- **TTS output:** `wav`, `mp3`, `flac`, `opus`, `aac`, `pcm`
- **STT input:** anything ffmpeg can decode

## GPU support

Ollama auto-detects NVIDIA GPUs via CUDA. If a GPU is available, models load into VRAM automatically. If VRAM is insufficient, ollama splits the model across GPU and CPU. On CPU-only machines it falls back gracefully.

STT and TTS run on CPU only — they're fast enough that GPU acceleration isn't needed for these workloads.
