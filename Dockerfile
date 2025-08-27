# Multi-stage build for Rails photo gallery application
# Use Ruby 3.1.4 for better Rails 7.0.x compatibility
FROM ruby:3.1.4-alpine AS base

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    postgresql-client \
    redis \
    tzdata \
    imagemagick \
    imagemagick-dev \
    vips \
    vips-dev \
    git \
    curl \
    nodejs \
    npm \
    yarn \
    bash

# Set environment variables
ENV RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

# Create app directory and user
RUN addgroup -g 1001 -S rails && \
    adduser -u 1001 -S rails -G rails

# Set working directory
WORKDIR /app

# Copy Gemfile (no Gemfile.lock for fresh gem resolution)
COPY --chown=rails:rails Gemfile ./

# Install gems (force clean install)
RUN bundle config set --local deployment 'false' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install && \
    bundle clean --force && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem

# Rails app doesn't need npm dependencies for this build
# Skip package.json copying and npm install

# Copy application code
COPY --chown=rails:rails . .

# Skip asset precompilation during build - will be done at runtime
# This avoids database/external service connection issues during build

# Create storage directories
RUN mkdir -p /app/storage /app/log /app/tmp && \
    chown -R rails:rails /app/storage /app/log /app/tmp

# Switch to non-root user
USER rails

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Copy and set up startup script
COPY --chown=rails:rails docker/startup.sh /app/
RUN chmod +x /app/startup.sh

# Default command - use startup script
CMD ["/app/startup.sh", "bundle", "exec", "puma", "-C", "config/puma.rb"]