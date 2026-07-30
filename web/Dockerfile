# TruthRelay Web — multi-stage Dockerfile (bun build → nginx)
#
# Build:  docker build -t truthrelay-web:latest -f web/Dockerfile .
# Run:    docker run --rm -p 5173:80 truthrelay-web:latest

# ---------- build stage ----------
FROM oven/bun:1 AS build

WORKDIR /build

# Install deps separately for layer caching.
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile

# Source + build.
COPY web/ ./
ENV VITE_API_URL=""
RUN bun run build

# ---------- runtime stage ----------
FROM nginx:1.27-alpine AS runtime

# Custom nginx config: serve /, reverse-proxy /api → api:8080, SPA fallback to /index.html.
COPY web/nginx.conf /etc/nginx/conf.d/default.conf

# Static assets from the build.
COPY --from=build /build/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]