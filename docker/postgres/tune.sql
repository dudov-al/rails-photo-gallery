-- ===========================================
-- PostgreSQL Performance Tuning
-- Optimized for Photography Gallery Workload
-- ===========================================

-- Connection and authentication settings
ALTER SYSTEM SET max_connections = '100';
ALTER SYSTEM SET superuser_reserved_connections = '3';

-- Memory settings (adjust based on server capacity)
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '16MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';

-- WAL (Write-Ahead Logging) settings for performance
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET checkpoint_completion_target = '0.9';
ALTER SYSTEM SET max_wal_size = '1GB';
ALTER SYSTEM SET min_wal_size = '256MB';

-- Query planner settings
ALTER SYSTEM SET random_page_cost = '1.1';  -- For SSD storage
ALTER SYSTEM SET effective_io_concurrency = '200';  -- For SSD storage
ALTER SYSTEM SET default_statistics_target = '100';

-- Logging settings for monitoring
ALTER SYSTEM SET log_min_duration_statement = '1000';  -- Log slow queries (>1s)
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET log_checkpoints = 'on';
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_lock_waits = 'on';
ALTER SYSTEM SET log_temp_files = '0';

-- Autovacuum settings for maintenance
ALTER SYSTEM SET autovacuum = 'on';
ALTER SYSTEM SET autovacuum_max_workers = '3';
ALTER SYSTEM SET autovacuum_naptime = '20s';
ALTER SYSTEM SET autovacuum_vacuum_threshold = '50';
ALTER SYSTEM SET autovacuum_analyze_threshold = '50';
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = '0.1';
ALTER SYSTEM SET autovacuum_analyze_scale_factor = '0.1';

-- Background writer settings
ALTER SYSTEM SET bgwriter_delay = '200ms';
ALTER SYSTEM SET bgwriter_lru_maxpages = '100';
ALTER SYSTEM SET bgwriter_lru_multiplier = '2.0';

-- Client connection defaults
ALTER SYSTEM SET default_transaction_isolation = 'read committed';
ALTER SYSTEM SET statement_timeout = '30s';  -- Prevent runaway queries
ALTER SYSTEM SET lock_timeout = '10s';       -- Prevent lock waits

-- Apply settings (requires restart)
SELECT pg_reload_conf();