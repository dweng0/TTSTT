{ pkgs, ... }:

{
  packages = with pkgs; [
    piper-tts
    openai-whisper-cpp
    ffmpeg
    sox
    curl
  ];

  languages.python = {
    enable = true;
    version = "3.12";
    venv = {
      enable = true;
      requirements = ./requirements.txt;
    };
  };

  processes = {
    stt = {
      exec = "python ${./stt-server/server.py}";
      process-compose = {
        readiness_probe = {
          http_get = {
            host = "127.0.0.1";
            port = 8000;
            path = "/health";
          };
          initial_delay_seconds = 5;
          period_seconds = 5;
        };
      };
    };
    tts = {
      exec = "python ${./tts-server/server.py}";
      process-compose = {
        readiness_probe = {
          http_get = {
            host = "127.0.0.1";
            port = 8001;
            path = "/health";
          };
          initial_delay_seconds = 3;
          period_seconds = 5;
        };
      };
    };
  };

  scripts.download-models.exec = ''
    set -euo pipefail
    MODEL_DIR="$DEVENV_ROOT/models"
    mkdir -p "$MODEL_DIR"

    # --- Whisper (STT) model ---
    WHISPER_MODEL="$MODEL_DIR/ggml-base.en.bin"
    if [ ! -f "$WHISPER_MODEL" ]; then
      echo "Downloading whisper base.en model..."
      curl -L -o "$WHISPER_MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
      echo "Downloaded: $WHISPER_MODEL"
    else
      echo "Whisper model already exists: $WHISPER_MODEL"
    fi

    # --- Piper (TTS) model ---
    PIPER_MODEL="$MODEL_DIR/en_US-lessac-medium.onnx"
    PIPER_CONFIG="$MODEL_DIR/en_US-lessac-medium.onnx.json"
    if [ ! -f "$PIPER_MODEL" ]; then
      echo "Downloading piper en_US-lessac-medium voice..."
      curl -L -o "$PIPER_MODEL" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
      curl -L -o "$PIPER_CONFIG" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
      echo "Downloaded: $PIPER_MODEL"
    else
      echo "Piper model already exists: $PIPER_MODEL"
    fi

    echo ""
    echo "All models ready!"
  '';

  enterShell = ''
    echo ""
    echo "=== Speech Server (CPU) ==="
    echo "  STT: whisper.cpp (base.en) -> http://localhost:8000/v1/audio/transcriptions"
    echo "  TTS: piper-tts (lessac)    -> http://localhost:8001/v1/audio/speech"
    echo ""
    echo "  Run 'download-models' to fetch models (required before first use)"
    echo "  Run 'devenv up' to start both servers"
    echo ""
  '';
}
