{ pkgs, ... }:

{
  packages = with pkgs; [
    piper-tts
    whisper-cpp
    ollama
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
    llm = {
      exec = "ollama serve";
      process-compose = {
        readiness_probe = {
          http_get = {
            host = "127.0.0.1";
            port = 11434;
            path = "/";
          };
          initial_delay_seconds = 3;
          period_seconds = 5;
        };
      };
    };
  };

  dotenv.enable = true;

  scripts.download-models.exec = ''
    set -euo pipefail
    MODEL_DIR="$DEVENV_ROOT/models"
    ENV_FILE="$DEVENV_ROOT/.env"
    mkdir -p "$MODEL_DIR"

    # --- Whisper (STT) model ---
    echo ""
    echo "=== Whisper STT Model ==="
    echo ""
    echo "  1) tiny.en      ~75MB   — fastest, lower accuracy"
    echo "  2) base.en     ~142MB   — good balance for English"
    echo "  3) small.en    ~466MB   — higher accuracy"
    echo "  4) medium.en    ~1.5GB  — high accuracy"
    echo "  5) large-v3     ~3.1GB  — best accuracy, multilingual"
    echo "  6) large-v3-turbo ~1.6GB — near-large accuracy, faster"
    echo ""
    read -rp "Select whisper model [1-6] (default: 2): " whisper_choice
    whisper_choice=''${whisper_choice:-2}

    case "$whisper_choice" in
      1) WHISPER_FILE="ggml-tiny.en.bin" ;;
      2) WHISPER_FILE="ggml-base.en.bin" ;;
      3) WHISPER_FILE="ggml-small.en.bin" ;;
      4) WHISPER_FILE="ggml-medium.en.bin" ;;
      5) WHISPER_FILE="ggml-large-v3.bin" ;;
      6) WHISPER_FILE="ggml-large-v3-turbo.bin" ;;
      *) echo "Invalid choice, using base.en"; WHISPER_FILE="ggml-base.en.bin" ;;
    esac

    WHISPER_PATH="$MODEL_DIR/$WHISPER_FILE"
    if [ ! -f "$WHISPER_PATH" ]; then
      echo "Downloading $WHISPER_FILE ..."
      curl -L -o "$WHISPER_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_FILE"
      echo "Downloaded: $WHISPER_PATH"
    else
      echo "Already exists: $WHISPER_PATH"
    fi

    # --- Piper (TTS) voice ---
    echo ""
    echo "=== Piper TTS Voice ==="
    echo ""
    echo "  1) lessac (low)       ~15MB  — fast, lower quality"
    echo "  2) lessac (medium)    ~50MB  — good balance"
    echo "  3) lessac (high)     ~100MB  — best quality"
    echo "  4) amy (medium)       ~50MB  — different US English speaker"
    echo "  5) alba (medium)      ~50MB  — Scottish English speaker"
    echo ""
    read -rp "Select piper voice [1-5] (default: 2): " piper_choice
    piper_choice=''${piper_choice:-2}

    case "$piper_choice" in
      1) PIPER_LANG="en/en_US"; PIPER_VOICE="lessac"; PIPER_QUALITY="low" ;;
      2) PIPER_LANG="en/en_US"; PIPER_VOICE="lessac"; PIPER_QUALITY="medium" ;;
      3) PIPER_LANG="en/en_US"; PIPER_VOICE="lessac"; PIPER_QUALITY="high" ;;
      4) PIPER_LANG="en/en_US"; PIPER_VOICE="amy"; PIPER_QUALITY="medium" ;;
      5) PIPER_LANG="en/en_GB"; PIPER_VOICE="alba"; PIPER_QUALITY="medium" ;;
      *) echo "Invalid choice, using lessac medium"; PIPER_LANG="en/en_US"; PIPER_VOICE="lessac"; PIPER_QUALITY="medium" ;;
    esac

    PIPER_NAME="en_US-''${PIPER_VOICE}-''${PIPER_QUALITY}"
    if [ "$PIPER_LANG" = "en/en_GB" ]; then
      PIPER_NAME="en_GB-''${PIPER_VOICE}-''${PIPER_QUALITY}"
    fi

    PIPER_MODEL="$MODEL_DIR/$PIPER_NAME.onnx"
    PIPER_CONFIG="$MODEL_DIR/$PIPER_NAME.onnx.json"
    if [ ! -f "$PIPER_MODEL" ]; then
      echo "Downloading $PIPER_NAME ..."
      curl -L -o "$PIPER_MODEL" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/$PIPER_LANG/$PIPER_VOICE/$PIPER_QUALITY/$PIPER_NAME.onnx"
      curl -L -o "$PIPER_CONFIG" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/$PIPER_LANG/$PIPER_VOICE/$PIPER_QUALITY/$PIPER_NAME.onnx.json"
      echo "Downloaded: $PIPER_MODEL"
    else
      echo "Already exists: $PIPER_MODEL"
    fi

    # --- Write .env so servers pick up the chosen models ---
    echo "WHISPER_MODEL_PATH=$WHISPER_PATH" > "$ENV_FILE"
    echo "PIPER_MODEL_PATH=$PIPER_MODEL" >> "$ENV_FILE"
    echo ""
    echo "Wrote model paths to .env"
    echo "All models ready! Run 'devenv up' to start services."
  '';

  enterShell = ''
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                     AIT — AI Trifecta                          ║"
    echo "║          Local AI services with OpenAI-compatible APIs          ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                ║"
    echo "║  STT  whisper.cpp    http://localhost:8000/v1/audio/transcriptions ║"
    echo "║  TTS  piper-tts     http://localhost:8001/v1/audio/speech      ║"
    echo "║  LLM  ollama        http://localhost:11434/v1/chat/completions ║"
    echo "║                                                                ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                ║"
    echo "║  1. download-models    pick & fetch STT/TTS models              ║"
    echo "║  2. ollama pull <model>  fetch an LLM (e.g. llama3.1:8b)      ║"
    echo "║  3. devenv up          start all services                      ║"
    echo "║                                                                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
  '';
}
