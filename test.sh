#!/bin/bash
set -e

IMAGE=joedefen/whisper-cuda-12
MODEL_DIR="$(pwd)/test-models"
MODEL="$MODEL_DIR/ggml-tiny.bin"

# Download tiny model (~75MB) if not present
mkdir -p "$MODEL_DIR"
if [ ! -f "$MODEL" ]; then
    echo "==> Downloading ggml-tiny model..."
    wget -q --show-progress -O "$MODEL" \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
fi

# Generate a 3-second silent WAV for a quick smoke test
echo "==> Generating test audio..."
ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 3 -q:a 0 -ac 1 -ar 16000 \
    /tmp/test-silence.wav 2>/dev/null

echo ""
echo "========== TEST 1: CUDA (--gpus all) =========="
docker run --rm --gpus all \
    -v "$MODEL_DIR":/models:ro \
    -v /tmp/test-silence.wav:/tmp/test.wav:ro \
    "$IMAGE" \
    -m /models/ggml-tiny.bin -f /tmp/test.wav \
    --no-prints 2>&1 | head -20
echo "==> Exit code: $?"

echo ""
echo "========== TEST 2: CPU fallback (no --gpus) =========="
docker run --rm \
    -v "$MODEL_DIR":/models:ro \
    -v /tmp/test-silence.wav:/tmp/test.wav:ro \
    "$IMAGE" \
    -m /models/ggml-tiny.bin -f /tmp/test.wav \
    --no-prints 2>&1 | head -20
echo "==> Exit code: $?"
