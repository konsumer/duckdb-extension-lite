# syntax=docker/dockerfile:1

ARG DUCKDB_VERSION=v1.5.0

# =============================================================================
# Build stage: compile the extension
# =============================================================================
FROM debian:bookworm-slim AS builder

ARG DUCKDB_VERSION
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build g++ python3 curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ext

# Copy source
COPY CMakeLists.txt .
COPY src/ src/

# Build the extension (CMake auto-downloads duckdb headers + footer script)
# Override platform to match the docker target architecture
RUN PLATFORM="linux_$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64)" && \
    cmake -G Ninja -B build \
      -DDUCKDB_VERSION=${DUCKDB_VERSION} \
      -DDUCKDB_PLATFORM=${PLATFORM} \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build

# Also download the duckdb CLI binary in the build stage (reuses curl/unzip)
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64) && \
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/duckdb_cli-linux-${ARCH}.zip" -o /tmp/duckdb.zip && \
    unzip /tmp/duckdb.zip -d /tmp/ && \
    chmod +x /tmp/duckdb

# =============================================================================
# Runtime stage: minimal image with duckdb CLI + extension
# =============================================================================
FROM debian:bookworm-slim

# Copy duckdb CLI
COPY --from=builder /tmp/duckdb /usr/local/bin/duckdb

# Copy the built extension and libduckdb.so (needed by the extension at dlopen time)
COPY --from=builder /ext/build/quack.duckdb_extension /ext/quack.duckdb_extension
COPY --from=builder /ext/build/_duckdb/libduckdb/libduckdb.so /usr/local/lib/libduckdb.so
RUN ldconfig

# Copy setup SQL
COPY src/setup.sql /ext/setup.sql

WORKDIR /data

ENTRYPOINT ["duckdb", "-unsigned", "-init", "/ext/setup.sql"]
