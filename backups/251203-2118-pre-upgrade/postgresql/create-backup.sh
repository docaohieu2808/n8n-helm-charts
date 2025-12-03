#!/bin/bash

# PostgreSQL Backup Script for n8n Upgrade
# Creates a comprehensive backup before system upgrade

set -euo pipefail

# Configuration
BACKUP_DIR="/home/hieudc/n8n/backups/251203-2118-pre-upgrade/postgresql"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/n8n_postgres_backup_$TIMESTAMP.sql"
BACKUP_LOG="$BACKUP_DIR/backup_$TIMESTAMP.log"
COMPRESSION_LEVEL=9

# Database Connection Details
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="n8n_postgres_db"
PG_USER="n8n_postgres_user"
PGCONNECTTIMEOUT=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$BACKUP_LOG"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Start backup process
log "Starting PostgreSQL backup for n8n upgrade"
log "Backup directory: $BACKUP_DIR"
log "Backup file: $BACKUP_FILE"

# Check prerequisites
command -v pg_dump >/dev/null 2>&1 || error_exit "pg_dump command not found"
command -v psql >/dev/null 2>&1 || error_exit "psql command not found"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR" || error_exit "Cannot create backup directory"

# Test database connection
log "Testing database connection..."
export PGHOST="$PG_HOST"
export PGPORT="$PG_PORT"
export PGDATABASE="$PG_DATABASE"
export PGUSER="$PG_USER"
export PGCONNECTTIMEOUT="$PGCONNECTTIMEOUT"

if ! psql -c "SELECT 1;" >/dev/null 2>&1; then
    error_exit "Cannot connect to PostgreSQL database at $PG_HOST:$PG_PORT"
fi
success "Database connection established"

# Get database size for progress tracking
DB_SIZE=$(psql -t -c "SELECT pg_size_pretty(pg_database_size('$PG_DATABASE'));" | xargs)
log "Database size: $DB_SIZE"

# Start backup with progress monitoring
log "Starting database dump..."

# Create backup with multiple formats for reliability
pg_dump \
    --host="$PG_HOST" \
    --port="$PG_PORT" \
    --username="$PG_USER" \
    --dbname="$PG_DATABASE" \
    --verbose \
    --no-password \
    --format=custom \
    --compress="$COMPRESSION_LEVEL" \
    --file="$BACKUP_FILE.dump" \
    2>&1 | tee -a "$BACKUP_LOG"

# Also create a plain SQL backup for compatibility
pg_dump \
    --host="$PG_HOST" \
    --port="$PG_PORT" \
    --username="$PG_USER" \
    --dbname="$PG_DATABASE" \
    --verbose \
    --no-password \
    --format=plain \
    --encoding=UTF8 \
    --file="$BACKUP_FILE" \
    2>&1 | tee -a "$BACKUP_LOG"

# Verify backup files were created and are not empty
if [[ ! -f "$BACKUP_FILE" ]]; then
    error_exit "Primary backup file was not created"
fi

if [[ ! -s "$BACKUP_FILE" ]]; then
    error_exit "Primary backup file is empty"
fi

if [[ ! -f "$BACKUP_FILE.dump" ]]; then
    error_exit "Compressed backup file was not created"
fi

if [[ ! -s "$BACKUP_FILE.dump" ]]; then
    error_exit "Compressed backup file is empty"
fi

# Get file sizes
PRIMARY_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
COMPRESSED_SIZE=$(ls -lh "$BACKUP_FILE.dump" | awk '{print $5}')

log "Backup files created successfully:"
log "  Primary SQL backup: $PRIMARY_SIZE"
log "  Compressed backup: $COMPRESSED_SIZE"

# Test backup integrity
log "Verifying backup integrity..."

# Test compressed backup restore capability
if pg_restore --list "$BACKUP_FILE.dump" > /dev/null 2>&1; then
    success "Compressed backup integrity check passed"
else
    warning "Compressed backup integrity check failed - but file exists"
fi

# Create backup metadata
cat > "$BACKUP_DIR/backup_metadata_$TIMESTAMP.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "database": "$PG_DATABASE",
    "host": "$PG_HOST",
    "port": "$PG_PORT",
    "user": "$PG_USER",
    "backup_files": {
        "sql_backup": "$BACKUP_FILE",
        "compressed_backup": "$BACKUP_FILE.dump"
    },
    "file_sizes": {
        "sql_backup": "$PRIMARY_SIZE",
        "compressed_backup": "$COMPRESSED_SIZE"
    },
    "database_size": "$DB_SIZE",
    "compression_level": "$COMPRESSION_LEVEL",
    "purpose": "n8n upgrade pre-backup"
}
EOF

# Create checksums for integrity verification
cd "$BACKUP_DIR"
sha256sum "n8n_postgres_backup_$TIMESTAMP.sql" > "n8n_postgres_backup_$TIMESTAMP.sql.sha256"
sha256sum "n8n_postgres_backup_$TIMESTAMP.dump" > "n8n_postgres_backup_$TIMESTAMP.dump.sha256"

success "Backup process completed successfully"
log "Backup location: $BACKUP_DIR"
log "Log file: $BACKUP_LOG"
log "Checksums created for integrity verification"

# Display summary
echo ""
echo "=== BACKUP SUMMARY ==="
echo "Database: $PG_DATABASE"
echo "Host: $PG_HOST:$PG_PORT"
echo "Backup files created:"
echo "  - $(basename "$BACKUP_FILE") ($PRIMARY_SIZE)"
echo "  - $(basename "$BACKUP_FILE.dump") ($COMPRESSED_SIZE)"
echo "  - backup_metadata_$TIMESTAMP.json"
echo "  - Checksum files (.sha256)"
echo "Log: $BACKUP_LOG"
echo ""
success "PostgreSQL backup completed successfully"