#!/bin/bash
set -euo pipefail

# Allow testing a candidate build without retagging :latest, e.g.
#   IMAGE=joedefen/whisper-cuda-12:v1.9.5-test ./test.sh
IMAGE="${IMAGE:-joedefen/whisper-cuda-12}"
MODEL_DIR="$(pwd)/test-models"
MODEL="$MODEL_DIR/ggml-tiny.bin"
AUDIO=/tmp/test-silence.wav

# Download tiny model (~75MB) if not present
mkdir -p "$MODEL_DIR"
if [ ! -f "$MODEL" ]; then
    echo "==> Downloading ggml-tiny model..."
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$MODEL" \
            https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
    else
        curl -fL -o "$MODEL" \
            https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
    fi
fi

# Generate a 3-second silent WAV for a quick smoke test.
# Fall back to the image's own ffmpeg when the host has none.
echo "==> Generating test audio..."
rm -f "$AUDIO"
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 3 -q:a 0 -ac 1 -ar 16000 \
        "$AUDIO" 2>/dev/null
else
    docker run --rm --entrypoint ffmpeg \
        -v "$AUDIO":/tmp/test.wav \
        "$IMAGE" \
        -y -f lavfi -i anullsrc=r=16000:cl=mono -t 3 -q:a 0 -ac 1 -ar 16000 \
        /tmp/test.wav 2>/dev/null
fi

# Run whisper-cli, keeping the full output so a failing exit code is not masked
# by `head` (which is what a plain pipe to `head` would do).
LAST_OUT=""
run_whisper() {
    local rc
    set +e
    LAST_OUT=$(docker run --rm "$@" "$IMAGE" \
        -m /models/ggml-tiny.bin -f /tmp/test.wav 2>&1)
    rc=$?
    set -e
    printf '%s\n' "$LAST_OUT" | head -25
    echo "==> Exit code: $rc"
    return "$rc"
}

echo ""
echo "========== TEST 1: CUDA (--gpus all) =========="
if ! run_whisper --gpus all \
    -v "$MODEL_DIR":/models:ro \
    -v "$AUDIO":/tmp/test.wav:ro; then
    echo "FAIL: CUDA run exited non-zero"
    exit 1
fi
if ! grep -q "loaded CUDA backend" <<<"$LAST_OUT"; then
    echo "FAIL: CUDA backend plugin was not loaded"
    exit 1
fi
if ! grep -q "using CUDA0 backend" <<<"$LAST_OUT"; then
    echo "FAIL: inference did not run on CUDA0"
    exit 1
fi

echo ""
echo "========== TEST 2: CPU fallback (no --gpus) =========="
if ! run_whisper \
    -v "$MODEL_DIR":/models:ro \
    -v "$AUDIO":/tmp/test.wav:ro; then
    echo "FAIL: CPU run exited non-zero"
    exit 1
fi
if ! grep -q "loaded CPU backend" <<<"$LAST_OUT"; then
    echo "FAIL: CPU backend plugin was not loaded"
    exit 1
fi
if grep -q "using CUDA0 backend" <<<"$LAST_OUT"; then
    echo "FAIL: CUDA backend was used even though --gpus was not passed"
    exit 1
fi

echo ""
echo "All smoke tests passed."
