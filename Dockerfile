# Stage 1: Builder
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y \
    git cmake build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Clone whisper.cpp pinned to a known-good commit (v1.8.3+)
ARG WHISPER_COMMIT=941bdabbe4561bc6de68981aea01bc5ab05781c5
RUN git clone https://github.com/ggerganov/whisper.cpp.git . && \
    git checkout ${WHISPER_COMMIT}

# Create the libcuda.so.1 symlink in the stub directory
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

# Configure with CUDA support
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="86;89" \
    -DBUILD_SHARED_LIBS=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_BENCHMARKS=OFF \
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

# Copy shared libraries
COPY --from=builder /app/build/src/libwhisper.so* /usr/lib/
COPY --from=builder /app/build/ggml/src/libggml*.so* /usr/lib/
COPY --from=builder /app/build/ggml/src/ggml-cuda/libggml-cuda.so* /usr/lib/

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
