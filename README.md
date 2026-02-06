# Whisper.cpp CUDA Dockerized

A high-performance, reproducible Docker container for [whisper.cpp](https://github.com/ggerganov/whisper.cpp) using NVIDIA CUDA 12. Optimized for modern GPUs (RTX 30-series/40-series).

## Performance
By utilizing the RTX 3060 Ti (Compute 8.6), subtitle generation and transcription are significantly accelerated:
* **CPU-only:** ~15 minutes
* **CUDA-accelerated:** ~90 seconds

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

2. Run Transcription

Mount your local folder containing audio files to the /data directory inside the container:
```
docker run --gpus all -v $(pwd)/my_audio:/data joedefen/whisper-cuda-12 \
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

## Configuration Details

* Base Image: nvidia/cuda:12.4.1-devel-ubuntu22.04
* CUDA Arch: 86;89 (RTX 3060 Ti, 3070, 3080, 3090, 40-series)
* Backend: GGML with CUDA support enabled (-DGGML_CUDA=ON)

## License
This project inherits the MIT License from whisper.cpp.
