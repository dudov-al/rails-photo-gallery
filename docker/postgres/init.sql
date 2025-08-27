-- PostgreSQL initialization script for photograph gallery

-- Ensure the photograph user exists and has proper permissions
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE rolname = 'photograph') THEN
      
      CREATE ROLE photograph LOGIN PASSWORD 'secure_password_change_me';
   END IF;
END
$do$;

-- Grant necessary permissions
ALTER USER photograph CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE photograph_production TO photograph;

-- Create extensions if they don't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Set up performance optimizations
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET track_activity_query_size = 2048;
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET log_min_duration_statement = 1000;

-- Reload configuration
SELECT pg_reload_conf();

-- Create a basic monitoring view
CREATE OR REPLACE VIEW database_stats AS
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'public';