# syntax=docker/dockerfile:1

ARG DUCKDB_VERSION=v1.5.0

# =============================================================================
# Stage 1: Download duckdb artifacts (cached unless DUCKDB_VERSION changes)
# =============================================================================
FROM debian:bookworm-slim AS downloads

ARG DUCKDB_VERSION
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# Download everything in one layer, keyed only on DUCKDB_VERSION + TARGETARCH
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64) && \
    mkdir -p /deps/src /deps/libduckdb && \
    # Amalgamated source headers
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-src.zip" -o /tmp/src.zip && \
    unzip -q /tmp/src.zip -d /deps/src && \
    # Shared library (for Linux linking)
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-linux-${ARCH}.zip" -o /tmp/lib.zip && \
    unzip -q /tmp/lib.zip -d /deps/libduckdb && \
    # Footer script
    curl -fsSL "https://gist.githubusercontent.com/konsumer/418053db631cd76d1856367672622636/raw/998ab6a524fb0a4cdf00f83a77135e443bf43537/add_duckdb_extension_footer.py" -o /deps/add_duckdb_extension_footer.py && \
    # DuckDB CLI binary
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/duckdb_cli-linux-${ARCH}.zip" -o /tmp/cli.zip && \
    unzip -q /tmp/cli.zip -d /deps && \
    chmod +x /deps/duckdb && \
    rm /tmp/*.zip

# =============================================================================
# Stage 2: Build toolchain (cached unless base image changes)
# =============================================================================
FROM debian:bookworm-slim AS toolchain

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build g++ python3 \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Stage 3: Compile extension (rebuilds only when src/ or CMakeLists.txt change)
# =============================================================================
FROM toolchain AS builder

ARG DUCKDB_VERSION
ARG TARGETARCH

WORKDIR /ext

# Copy pre-downloaded deps (cached from stage 1)
COPY --from=downloads /deps /deps

# Copy build definition first (changes less often than source)
COPY CMakeLists.txt .

# Copy source files (the part that actually changes between builds)
COPY src/ src/

# Build — cmake skips downloads since deps are pre-populated via DUCKDB_DEPS_DIR
RUN PLATFORM="linux_$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64)" && \
    cmake -G Ninja -B build \
      -DDUCKDB_VERSION=${DUCKDB_VERSION} \
      -DDUCKDB_PLATFORM=${PLATFORM} \
      -DDUCKDB_DEPS_DIR=/deps \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build

# =============================================================================
# Runtime stage: minimal image with duckdb CLI + extension
# =============================================================================
FROM debian:bookworm-slim

# Copy duckdb CLI (from downloads stage, independent of compilation)
COPY --from=downloads /deps/duckdb /usr/local/bin/duckdb

# Copy libduckdb.so (from downloads stage, independent of compilation)
COPY --from=downloads /deps/libduckdb/libduckdb.so /usr/local/lib/libduckdb.so
RUN ldconfig

# Copy the built extension
COPY --from=builder /ext/build/quack.duckdb_extension /ext/quack.duckdb_extension

# Copy setup SQL
COPY src/setup.sql /ext/setup.sql

WORKDIR /data

ENTRYPOINT ["duckdb", "-unsigned", "-init", "/ext/setup.sql"]
