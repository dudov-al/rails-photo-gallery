# ===========================================
# Production-Ready Multi-Stage Rails Dockerfile
# Optimized for Rails 7.1.x Photography Gallery
# ===========================================

# ===========================================
# Stage 1: Base Image with System Dependencies
# ===========================================
FROM ruby:3.1.4-alpine3.18 AS base

# Install critical security updates
RUN apk update && apk upgrade

# Install system dependencies
RUN apk add --no-cache \
    # Build dependencies
    build-base \
    linux-headers \
    # Database
    postgresql15-dev \
    postgresql15-client \
    # Image processing
    vips-dev \
    vips-tools \
    # Essential tools
    git \
    curl \
    bash \
    tzdata \
    # Node.js and package managers
    nodejs \
    npm \
    yarn && \
    # Clean package cache to reduce image size
    rm -rf /var/cache/apk/*

# Create non-root user with specific UID/GID for security
RUN addgroup -g 1001 -S rails && \
    adduser -u 1001 -S rails -G rails -h /app

# Configure Ruby and Bundler for optimal performance
ENV BUNDLE_APP_CONFIG="/usr/local/bundle" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3"

# ===========================================
# Stage 2: Dependencies Installation
# ===========================================
FROM base AS dependencies

WORKDIR /app

# Copy dependency files first for better Docker layer caching
COPY Gemfile ./

# Install Ruby gems with simplified configuration
RUN bundle config set --global without 'development test' && \
    bundle config set --global jobs 4 && \
    bundle config set --global retry 3 && \
    bundle install --retry=3 && \
    # Remove unnecessary files to reduce image size
    bundle clean --force && \
    rm -rf /usr/local/bundle/cache

# Install Node.js dependencies if package.json exists
COPY package*.json yarn.lock* ./
RUN if [ -f package.json ]; then \
    npm ci --only=production --no-audit --no-fund && \
    npm cache clean --force; \
    fi

# ===========================================
# Stage 3: Application Build
# ===========================================
FROM dependencies AS builder

# Copy application source code
COPY --chown=rails:rails . .

# Set production environment for build
ENV RAILS_ENV=production \
    NODE_ENV=production \
    SECRET_KEY_BASE=9a585637405072662984244470adb98149f05e4bf7a95901e00d47289bd283185b5b0e21dc3b5a942ed0cf6973ed515d86de7e3d17cec8471a8298a4a026740d

# Create necessary directories with proper permissions
RUN mkdir -p /app/log /app/tmp/pids /app/tmp/cache /app/public/assets /app/storage && \
    chown -R rails:rails /app/log /app/tmp /app/public /app/storage

# Switch to non-root user for build process
USER rails

# Precompile assets with security optimizations
RUN RAILS_ENV=production SECRET_KEY_BASE=9a585637405072662984244470adb98149f05e4bf7a95901e00d47289bd283185b5b0e21dc3b5a942ed0cf6973ed515d86de7e3d17cec8471a8298a4a026740d \
    bundle exec rails assets:precompile && \
    # Remove source maps and debugging info for production
    find public/assets -name "*.map" -delete

# ===========================================
# Stage 4: Production Runtime
# ===========================================
FROM base AS runtime

# Install only runtime dependencies
RUN apk add --no-cache \
    postgresql15-client \
    vips=~8.14 \
    curl \
    bash \
    tzdata && \
    rm -rf /var/cache/apk/*

# Set production environment variables
ENV RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true \
    MALLOC_ARENA_MAX=2

# Create app directory and set permissions
WORKDIR /app
RUN chown rails:rails /app

# Copy bundle from dependencies stage
COPY --from=dependencies --chown=rails:rails /usr/local/bundle /usr/local/bundle

# Copy built application from builder stage
COPY --from=builder --chown=rails:rails /app .

# Create and set permissions for runtime directories
RUN mkdir -p /app/tmp/pids /app/tmp/sockets && \
    chown -R rails:rails /app/tmp

# Switch to non-root user
USER rails

# Expose port 3000
EXPOSE 3000

# Add comprehensive health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Add signal handling for graceful shutdowns
STOPSIGNAL SIGTERM

# Add labels for better container management
LABEL maintainer="Rails Photography Gallery" \
      version="1.0.0" \
      description="Production-ready Rails photography gallery application" \
      org.opencontainers.image.source="https://github.com/yourrepo/photograph"

# Use exec form for proper signal handling
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]