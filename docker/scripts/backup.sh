#!/bin/bash
# ===========================================
# PostgreSQL Backup Script
# ===========================================

set -e

# Configuration
DB_NAME="photograph_production"
DB_USER="photograph"
BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/photograph_backup_${TIMESTAMP}.sql"
BACKUP_COMPRESSED="${BACKUP_FILE}.gz"

# Retention settings (keep backups for 30 days)
RETENTION_DAYS=30

echo "Starting backup process..."

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Create database dump
echo "Creating database dump..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h db \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    --verbose \
    --clean \
    --if-exists \
    --create \
    --compress=0 \
    > "${BACKUP_FILE}"

# Compress the backup
echo "Compressing backup..."
gzip "${BACKUP_FILE}"

# Verify backup was created successfully
if [ -f "${BACKUP_COMPRESSED}" ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_COMPRESSED}" | cut -f1)
    echo "Backup created successfully: ${BACKUP_COMPRESSED} (${BACKUP_SIZE})"
else
    echo "ERROR: Backup file was not created!" >&2
    exit 1
fi

# Clean up old backups
echo "Cleaning up old backups (keeping last ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "photograph_backup_*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete

# List current backups
echo "Current backups:"
ls -lah "${BACKUP_DIR}"/photograph_backup_*.sql.gz 2>/dev/null || echo "No backups found"

echo "Backup process completed successfully!"

# Optional: Upload to cloud storage (uncomment and configure as needed)
# echo "Uploading to cloud storage..."
# aws s3 cp "${BACKUP_COMPRESSED}" s3://your-backup-bucket/database/ --storage-class STANDARD_IA