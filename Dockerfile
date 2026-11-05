# Multi-stage production Dockerfile
# Stage 1: Dependency resolution and caching
FROM node:20-alpine AS dependencies

WORKDIR /usr/src/app

# Install build dependencies if needed for native modules
RUN apk add --no-cache python3 make g++

# Copy package manifests
COPY package.json package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev && npm cache clean --force

# ==========================================
# Stage 2: Production runner (minimal, non-root)
# ==========================================
FROM node:20-alpine AS runner

WORKDIR /usr/src/app

# Install curl and dumb-init for proper signal handling and container healthchecks
RUN apk add --no-cache dumb-init curl

# Create non-root user and group with explicit UID/GID for least privilege
RUN addgroup -g 10001 -S conduit && \
    adduser -u 10001 -S conduit -G conduit

# Set runtime environment
ENV NODE_ENV=production \
    PORT=3000

# Copy node_modules from dependencies stage with non-root ownership
COPY --chown=conduit:conduit --from=dependencies /usr/src/app/node_modules ./node_modules

# Copy application source code
COPY --chown=conduit:conduit package.json ./
COPY --chown=conduit:conduit app.js ./
COPY --chown=conduit:conduit bin ./bin
COPY --chown=conduit:conduit config ./config
COPY --chown=conduit:conduit controllers ./controllers
COPY --chown=conduit:conduit middlewares ./middlewares
COPY --chown=conduit:conduit models ./models
COPY --chown=conduit:conduit routes ./routes
COPY --chown=conduit:conduit swagger.json ./

# Switch to non-root user
USER conduit

# Expose internal application port
EXPOSE 3000

# Container healthcheck targeting /health endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Execute app via dumb-init for graceful shutdown signal propagation (SIGTERM/SIGINT)
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "bin/www"]
