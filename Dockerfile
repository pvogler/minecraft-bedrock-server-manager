# Stage 0: Fetch the standalone Docker Compose binary from the upstream release.
# Only `docker compose` is needed at runtime (everything else goes through the
# Docker API via dockerode), so we avoid Alpine's docker-cli/docker-cli-compose
# packages, which lag upstream and pull in a much larger vulnerable surface.
FROM node:26-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80 AS compose

# renovate: datasource=github-releases depName=docker/compose
ARG COMPOSE_VERSION=v5.5.1

RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  compose_arch=x86_64 ;; \
      aarch64) compose_arch=aarch64 ;; \
      armv7l)  compose_arch=armv7 ;; \
      *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}"; \
    wget -qO /docker-compose "${base}/docker-compose-linux-${compose_arch}"; \
    wget -qO /docker-compose.sha256 "${base}/docker-compose-linux-${compose_arch}.sha256"; \
    awk '{ print $1 "  /docker-compose" }' /docker-compose.sha256 | sha256sum -c -; \
    chmod 0755 /docker-compose; \
    /docker-compose version

# Stage 1: Build Stage
FROM node:26-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80 AS builder

WORKDIR /app

# Copy package files and install ALL dependencies
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Run build steps
# setup-websocket.js downloads socket.io.js to public/
RUN node setup-websocket.js
RUN npm run build:css:prod
RUN npm run copy-assets

# Stage 2: Production Stage
FROM node:26-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80

WORKDIR /app

# docker CLI + compose plugin, used to manage per-instance docker-compose.yml files
#RUN apk add --no-cache docker-cli docker-cli-compose

# Standalone Compose binary, used to manage per-instance docker-compose.yml files
COPY --from=compose /docker-compose /usr/local/bin/docker-compose

# Copy only production dependencies
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy application source and built assets from builder
COPY --from=builder /app/server.js ./
COPY --from=builder /app/public ./public
# Create temp and logs directories
RUN mkdir -p temp/addon-uploads temp/uploads logs

# Expose port
EXPOSE 3001

# Set environment variables
ENV DATA_DIR=/app/minecraft-data
ENV NODE_ENV=production
# No docker CLI in this image, so use the standalone Compose binary
ENV COMPOSE_CMD=docker-compose

# Run the application
CMD ["node", "server.js"]
