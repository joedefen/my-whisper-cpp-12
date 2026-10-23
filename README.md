# Whisper.cpp CUDA Dockerized

A high-performance, reproducible Docker container for [whisper.cpp](https://github.com/ggml-org/whisper.cpp) using NVIDIA CUDA 12. Optimized for modern GPUs (RTX 30-series/40-series). Currently pinned to whisper.cpp **v1.9.5**.

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

*Tip: use `ggml-base.en.bin` if your audio is English-only, or `ggml-large-v3-turbo.bin` for the best accuracy. See [the model list](https://github.com/ggml-org/whisper.cpp/tree/master/models) for all options.*

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
`master`, so builds stay reproducible and don't break unexpectedly. The image
currently pins **v1.9.5** (released 2026-10-06), the latest stable release —
commit `d1be6fde` (the commit the `v1.9.5` annotated tag points at). v1.9.5 is a
maintenance release that bundles ggml v0.26.0 with CUDA/kernel fixes.

To move to a newer version:

1. **Check for new versions.** Look at the [releases page](https://github.com/ggml-org/whisper.cpp/releases)
   (prefer a stable tagged release like `v1.9.5` over a raw nightly). Get the
   commit SHA for the tag. Note that `whisper.cpp` tags are annotated, so use
   the **peeled** commit (the `^{}` line), not the tag object SHA:
   ```
   git ls-remote https://github.com/ggml-org/whisper.cpp.git 'refs/tags/v1.9.5*'
   ```
   The output looks like:
   ```
   d2a764c6...  refs/tags/v1.9.5      <- tag object (do not pin this)
   d1be6fde...  refs/tags/v1.9.5^{}   <- commit to pin this
   ```

2. **Update the pin.** In the `Dockerfile`, change the `WHISPER_COMMIT` build arg
   (and the comment next to it) to the new SHA:
   ```dockerfile
   ARG WHISPER_COMMIT=<new-commit-sha>
   ```

3. **Rebuild and test.** Build the image, then run the smoke tests, which cover
   both the CUDA and CPU-fallback paths. `test.sh` also verifies that the CUDA
   plugin was loaded and that inference actually ran on `CUDA0`, and that the CPU
   plugin is used when `--gpus` is omitted:
   ```
   docker build -t joedefen/whisper-cuda-12 .
   ./test.sh
   ```
   To test a candidate build without retagging `latest`, override `IMAGE`:
   ```
   docker build -t joedefen/whisper-cuda-12:candidate .
   IMAGE=joedefen/whisper-cuda-12:candidate ./test.sh
   ```

*Note: the build uses `GGML_BACKEND_DL=ON` (CUDA is a runtime plugin). Since
v1.9.x, `CMAKE_LIBRARY_OUTPUT_DIRECTORY` points at `build/bin`, so **all** shared
libraries are emitted there (previously `build/src` and `build/ggml/src`). The
Dockerfile copies `build/bin/whisper-cli`, `libwhisper.so*`, `libggml.so*`,
`libggml-base.so*`, plus the backend plugins `libggml-cuda.so` / `libggml-cpu.so`
into `/usr/lib/ggml-backends/`. The build also produces `libparakeet.so`, but
`whisper-cli` does not link it, so it is intentionally not copied. If a future
upstream commit renames or relocates these files, the `COPY` steps in the
Dockerfile will need updating.*

## Configuration Details

* whisper.cpp: v1.9.5 (pinned commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`)
* GGML: v0.26.0 (bundled with whisper.cpp v1.9.5)
* Base Image: nvidia/cuda:12.4.1-devel-ubuntu22.04
* CUDA Arch: 86;89 (RTX 3060 Ti, 3070, 3080, 3090, 40-series)
* Backend: GGML with CUDA support enabled (-DGGML_CUDA=ON)
* Examples: the whole examples tree is compiled, but only `whisper-cli` is copied
  into the final image; tests are disabled

## License
This project inherits the MIT License from whisper.cpp.



