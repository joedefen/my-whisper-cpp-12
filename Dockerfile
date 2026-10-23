# Stage 1: Builder
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y \
    git cmake build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Clone whisper.cpp pinned to a known-good commit for reproducibility.
# Pinned to the v1.9.5 release commit (2026-10-06), the latest stable release.
# The SHA below is the commit the v1.9.5 annotated tag points at (i.e. the
# peeled `refs/tags/v1.9.5^{}` commit, not the tag object).
# To update this pin (check for releases, get the SHA, rebuild/test), see the
# "Updating the pinned whisper.cpp version" section in README.md.
ARG WHISPER_COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037
RUN git clone https://github.com/ggml-org/whisper.cpp.git . && \
    git checkout ${WHISPER_COMMIT}

# Create the libcuda.so.1 symlink in the stub directory
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

# Configure with CUDA support (GGML_BACKEND_DL makes CUDA a runtime
# plugin via dlopen so the image works with or without a GPU)
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_BACKEND_DIR=/usr/lib/ggml-backends \
    -DGGML_NATIVE=OFF \
    -DCMAKE_CUDA_ARCHITECTURES="86;89" \
    -DBUILD_SHARED_LIBS=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64/stubs \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs"

# Build everything (this will include the main example)
RUN cmake --build build --config Release -j $(nproc)

# Stage 2: Runtime
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04
RUN apt-get update && apt-get install -y \
    libgomp1 \
    ffmpeg \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary - the main executable should be in build/bin/
COPY --from=builder /app/build/bin/whisper-cli /usr/local/bin/whisper-cli

# Copy shared libraries (core libs that are always needed).
# Since whisper.cpp v1.9.x, CMAKE_LIBRARY_OUTPUT_DIRECTORY is set to build/bin,
# so all shared libraries live there (previously build/src and build/ggml/src).
COPY --from=builder /app/build/bin/libwhisper.so* /usr/lib/
COPY --from=builder /app/build/bin/libggml.so* /usr/lib/
COPY --from=builder /app/build/bin/libggml-base.so* /usr/lib/

# Backend plugins (CUDA, CPU) built with GGML_BACKEND_DL land in build/bin/
RUN mkdir -p /usr/lib/ggml-backends
COPY --from=builder /app/build/bin/libggml-cuda.so /usr/lib/ggml-backends/
COPY --from=builder /app/build/bin/libggml-cpu.so /usr/lib/ggml-backends/

# Run ldconfig to update library cache
RUN ldconfig

# Set up environment
ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH
ENV WHISPER_CLI=/usr/local/bin/whisper-cli

# Create a non-root user for security
RUN useradd -m -u 1000 -s /bin/bash whisperuser && \
    chown -R whisperuser:whisperuser /app
USER whisperuser

# Set entrypoint
ENTRYPOINT ["whisper-cli"]


