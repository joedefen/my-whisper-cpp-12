# Whisper.cpp CUDA Dockerized

A high-performance, reproducible Docker container for [whisper.cpp](https://github.com/ggerganov/whisper.cpp) using NVIDIA CUDA 12. Optimized for modern GPUs (RTX 30-series/40-series).

## Performance
By utilizing the RTX 3060 Ti (Compute 8.6), subtitle generation and transcription are significantly accelerated:
* **CPU-only:** ~15 minutes
* **CUDA-accelerated:** ~90 seconds

*CPU-only is the fallback and does not need a GPU. The image still builds the CPU
backend, so it works on machines without an NVIDIA GPU (or drivers). Just omit
`--gpus all` from the `docker run` command, as shown in [How to Use](#how-to-use).*

---

## Prerequisites

Before running this container, ensure your host machine (e.g., Debian 13) has:
1. **NVIDIA Drivers:** Version 550+ recommended.
2. **Docker:** [Installed and running](https://docs.docker.com/engine/install/).
3. **NVIDIA Container Toolkit:** This is required to "pass" the GPU into the container.
   ```bash
   # Check if installed
   nvidia-smi
   docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
   ```

---

## How to Use
1. Pull the Image
```
docker pull joedefen/whisper-cuda-12:latest
```

2. Download a Model

whisper.cpp needs a GGML model file. Download one (e.g. `base`) into
`my_audio/models/`, which you will mount into the container below:

```
mkdir -p my_audio/models
wget -P my_audio/models \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

*Tip: use `ggml-base.en.bin` if your audio is English-only, or `ggml-large-v3-turbo.bin` for the best accuracy. See [the model list](https://github.com/ggerganov/whisper.cpp#ggml-models) for all options.*

3. Run Transcription

Mount your local folder containing the model and audio files to the `/data`
directory inside the container:
```
docker run --gpus all -v $(pwd)/my_audio:/data joedefen/whisper-cuda-12:latest \
  -m /data/models/ggml-base.bin \
  -f /data/audio_sample.wav \
  --output-srt
```

The resulting `.srt` subtitle file is written next to the input audio (in
`my_audio/` on your host).

**CPU-only (no GPU):** simply omit `--gpus all`. The image includes the CPU
backend, so it runs anywhere Docker runs:
```
docker run -v $(pwd)/my_audio:/data joedefen/whisper-cuda-12:latest \
  -m /data/models/ggml-base.bin \
  -f /data/audio_sample.wav \
  --output-srt
```

## Build it Locally

If you want to build the image yourself (e.g., to target a specific CUDA architecture):

1. Clone the repo:
```
git clone https://github.com/joedefen/my-whisper-cpp-12.git
cd my-whisper-cpp-12
```

2. Build:
```
docker build -t joedefen/whisper-cuda-12 .
```

*Note: The Dockerfile is currently optimized for Ampere (RTX 30-series) and Ada (RTX 40-series).*

## Updating the pinned whisper.cpp version

The Dockerfile pins whisper.cpp to a specific commit rather than tracking
`master`, so builds stay reproducible and don't break unexpectedly. The commit
currently pinned (`941bdabb`) sits between v1.8.3 (2026-01-15) and
v1.8.4 (2026-03-19) — roughly v1.8.3+.

To move to a newer version:


1. **Check for new versions.** Look at the [releases page](https://github.com/ggml-org/whisper.cpp/releases)
   (prefer a tagged release like `v1.9.4` over a raw nightly). Get the commit SHA
   for the tag — either from the release page, or:
   ```
   git ls-remote https://github.com/ggml-org/whisper.cpp.git refs/tags/v1.9.4
   ```

2. **Update the pin.** In the `Dockerfile`, change the `WHISPER_COMMIT` build arg
   (and the comment next to it) to the new SHA:
   ```dockerfile
   ARG WHISPER_COMMIT=<new-commit-sha>
   ```

3. **Rebuild and test.** Build the image, then run the smoke tests, which cover
   both the CUDA and CPU-fallback paths:
   ```
   docker build -t joedefen/whisper-cuda-12 .
   ./test.sh
   ```

*Note: the build uses `GGML_BACKEND_DL=ON` (CUDA is a runtime plugin) and copies
specific artifacts (`build/bin/whisper-cli`, `libwhisper.so*`, `libggml*.so*`, and
`libggml-cuda.so` / `libggml-cpu.so`). If a future upstream commit renames or
relocates these files, the `COPY` steps in the Dockerfile will need updating.*

## Configuration Details

* Base Image: nvidia/cuda:12.4.1-devel-ubuntu22.04
* CUDA Arch: 86;89 (RTX 3060 Ti, 3070, 3080, 3090, 40-series)
* Backend: GGML with CUDA support enabled (-DGGML_CUDA=ON)

## License
This project inherits the MIT License from whisper.cpp.



