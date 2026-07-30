# TruthRelay API — multi-stage Dockerfile
#
# Build:  docker build -t truthrelay-api:latest -f api/Dockerfile .
# Run:    docker run --rm -p 8080:8080 -v truthrelay-data:/data \
#             -e TRUTHRELAY_BIND=0.0.0.0:8080 \
#             -e TRUTHRELAY_DB=/data/truthrelay.db \
#             truthrelay-api:latest

# ---------- build stage ----------
FROM rust:latest AS build

WORKDIR /build

# System deps for sqlx-sqlite + ed25519-dalek (no OpenSSL needed).
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Cache dependency layer: copy manifests first, build a stub bin, then drop it.
COPY api/Cargo.toml api/Cargo.lock ./
RUN mkdir -p src/bin \
 && echo 'fn main() {}' > src/main.rs \
 && echo '' > src/lib.rs \
 && cargo build --release --bin truthrelay \
 && rm -rf src target/release/truthrelay target/release/deps/truthrelay-*

# Real source.
COPY api/src ./src

# Touch everything so cargo re-runs (timestamp fix for the cache trick above).
RUN find src -type f -exec touch {} +
RUN cargo build --release --locked --bin truthrelay

# ---------- runtime stage ----------
FROM debian:bookworm-slim AS runtime

# CA certs, curl (for HEALTHCHECK), and tini (PID 1 signal handling).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 1001 truthrelay \
 && useradd  --system --uid 1001 --gid truthrelay truthrelay \
 && mkdir -p /data /keys \
 && chown -R truthrelay:truthrelay /data /keys

WORKDIR /app

COPY --from=build /build/target/release/truthrelay /usr/local/bin/truthrelay

USER truthrelay

ENV TRUTHRELAY_BIND=0.0.0.0:8080 \
    TRUTHRELAY_DB=/data/truthrelay.db \
    TRUTHRELAY_KEYS_DIR=/keys \
    RUST_LOG=info

EXPOSE 8080

VOLUME ["/data", "/keys"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["truthrelay", "serve"]