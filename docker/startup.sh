#!/bin/bash
set -e

echo "Starting Rails Photo Gallery application..."

# Wait for database to be ready
echo "Waiting for database to be ready..."
while ! pg_isready -h postgres -p 5432 -U $POSTGRES_USER; do
  echo "Waiting for postgres to be ready..."
  sleep 2
done
echo "Database is ready!"

# Wait for Redis to be ready
echo "Waiting for Redis to be ready..."
while ! redis-cli -h redis ping > /dev/null 2>&1; do
  echo "Waiting for Redis to be ready..."
  sleep 2
done
echo "Redis is ready!"

# Setup database if needed
echo "Setting up database..."
bundle exec rails db:create db:migrate

# Precompile assets if not already done
if [ ! -d "/app/public/assets" ]; then
  echo "Precompiling assets..."
  bundle exec rails assets:precompile
  echo "Assets precompiled successfully!"
fi

# Start the application
echo "Starting Rails application..."
exec "$@"