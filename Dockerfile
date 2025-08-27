# Multi-stage build for Rails photo gallery application
FROM ruby:3.2.0-alpine AS base

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    tzdata \
    imagemagick \
    imagemagick-dev \
    vips \
    vips-dev \
    git \
    curl \
    nodejs \
    npm \
    yarn

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

# Copy Gemfile and Gemfile.lock
COPY --chown=rails:rails Gemfile Gemfile.lock ./

# Install gems
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install && \
    bundle clean --force && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem

# Copy package.json if exists (for any npm dependencies)
COPY --chown=rails:rails package*.json ./
RUN if [ -f package.json ]; then npm ci --production && npm cache clean --force; fi

# Copy application code
COPY --chown=rails:rails . .

# Precompile assets
RUN SECRET_KEY_BASE=precompile_placeholder bundle exec rails assets:precompile

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

# Default command
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]