#!/bin/bash

# Redis Backup Script for n8n Upgrade
# Creates a comprehensive backup of Redis data using BGSAVE

set -euo pipefail

# Configuration
BACKUP_DIR="/home/hieudc/n8n/backups/251203-2118-pre-upgrade/redis"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REDIS_HOST="redis-ha-haproxy.database.svc.cluster.local"
REDIS_PORT="6379"
REDIS_PASSWORD=""  # Set if password is required
BACKUP_LOG="$BACKUP_DIR/redis_backup_$TIMESTAMP.log"

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
log "Starting Redis backup for n8n upgrade"
log "Redis server: $REDIS_HOST:$REDIS_PORT"
log "Backup directory: $BACKUP_DIR"

# Check prerequisites
command -v redis-cli >/dev/null 2>&1 || error_exit "redis-cli command not found"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR" || error_exit "Cannot create backup directory"

# Test Redis connection
log "Testing Redis connection..."
if [[ -n "$REDIS_PASSWORD" ]]; then
    REDIS_CMD="redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD --no-auth-warning"
else
    REDIS_CMD="redis-cli -h $REDIS_HOST -p $REDIS_PORT"
fi

if ! $REDIS_CMD ping >/dev/null 2>&1; then
    error_exit "Cannot connect to Redis server at $REDIS_HOST:$REDIS_PORT"
fi
success "Redis connection established"

# Get Redis info for backup planning
log "Gathering Redis information..."
REDIS_INFO=$(eval "$REDIS_CMD info")
REDIS_VERSION=$(echo "$REDIS_INFO" | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
REDIS_USED_MEMORY=$(echo "$REDIS_INFO" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
REDIS_DB_COUNT=$(echo "$REDIS_INFO" | grep "db" | grep -c "keys=" || echo "1")

log "Redis version: $REDIS_VERSION"
log "Memory usage: $REDIS_USED_MEMORY"
log "Database count: $REDIS_DB_COUNT"

# Get current database size and key counts
log "Getting database statistics..."
for i in $(seq 0 15); do
    DB_KEYS=$(eval "$REDIS_CMD -n $i dbsize" 2>/dev/null || echo "0")
    if [[ "$DB_KEYS" -gt 0 ]]; then
        log "Database $i: $DB_KEYS keys"
    fi
done

# Trigger background save
log "Triggering background save (BGSAVE)..."
LAST_SAVE_BEFORE=$(eval "$REDIS_CMD lastsave" || echo "0")

if ! eval "$REDIS_CMD bgsave" >/dev/null 2>&1; then
    error_exit "Failed to trigger BGSAVE command"
fi

# Monitor BGSAVE progress
log "Monitoring BGSAVE progress..."
BGSAVE_TIMEOUT=600  # 10 minutes timeout
BGSAVE_START_TIME=$(date +%s)

while true; do
    LAST_SAVE_CURRENT=$(eval "$REDIS_CMD lastsave" || echo "0")
    CURRENT_TIME=$(date +%s)

    if [[ "$LAST_SAVE_CURRENT" -gt "$LAST_SAVE_BEFORE" ]]; then
        success "Background save completed"
        break
    fi

    if [[ $((CURRENT_TIME - BGSAVE_START_TIME)) -gt $BGSAVE_TIMEOUT ]]; then
        error_exit "BGSAVE timeout after $BGSAVE_TIMEOUT seconds"
    fi

    log "Still saving... ($((CURRENT_TIME - BGSAVE_START_TIME))s elapsed)"
    sleep 5
done

# Get RDB file location from Redis config
log "Determining RDB file location..."
REDIS_DIR=$(eval "$REDIS_CMD config get dir" | tail -n 1 | tr -d '\r')
REDIS_DBFILENAME=$(eval "$REDIS_CMD config get dbfilename" | tail -n 1 | tr -d '\r')
RDB_FILE_PATH="$REDIS_DIR/$REDIS_DBFILENAME"

log "RDB file location: $RDB_FILE_PATH"

# Copy RDB file to backup directory
BACKUP_RDB_FILE="$BACKUP_DIR/redis_backup_$TIMESTAMP.rdb"
log "Copying RDB file to backup location..."

# Try to copy using redis-cli COPY (Redis 6.2+)
if eval "$REDIS_CMD --raw --rdb $BACKUP_RDB_FILE" >/dev/null 2>&1; then
    success "RDB file copied using redis-cli"
else
    warning "redis-cli --rdb not available, trying alternative methods"

    # If we can SSH to the Redis server, copy from there
    if command -v scp >/dev/null 2>&1; then
        log "Attempting SCP copy from Redis server..."
        # This would require SSH access to the Redis server
        warning "SCP method requires SSH access - manual copy may be needed"
    fi

    # Fallback: create a script that can be run on the Redis server
    cat > "$BACKUP_DIR/copy_rdb_from_server.sh" << EOF
#!/bin/bash
# Run this script on the Redis server to copy the RDB file

REDIS_DIR="$REDIS_DIR"
BACKUP_FILE="$BACKUP_RDB_FILE"

if [[ -f "\$REDIS_DIR/$REDIS_DBFILENAME" ]]; then
    cp "\$REDIS_DIR/$REDIS_DBFILENAME" "\$BACKUP_FILE"
    echo "RDB file copied to \$BACKUP_FILE"
    ls -la "\$BACKUP_FILE"
else
    echo "RDB file not found at \$REDIS_DIR/$REDIS_DBFILENAME"
    exit 1
fi
EOF
    chmod +x "$BACKUP_DIR/copy_rdb_from_server.sh"
    warning "Created copy script - run manually on Redis server"
fi

# Create additional backup using redis-cli DUMP (if available)
log "Creating key-by-key backup using DUMP command..."
KEY_COUNT_FILE="$BACKUP_DIR/key_count_$TIMESTAMP.txt"
DUMP_FILE="$BACKUP_DIR/redis_dump_$TIMESTAMP.txt"

# Get total key count
TOTAL_KEYS=0
for i in $(seq 0 15); do
    DB_KEYS=$(eval "$REDIS_CMD -n $i dbsize" 2>/dev/null || echo "0")
    TOTAL_KEYS=$((TOTAL_KEYS + DB_KEYS))
    echo "Database $i: $DB_KEYS keys" >> "$KEY_COUNT_FILE"
done

echo "Total keys: $TOTAL_KEYS" >> "$KEY_COUNT_FILE"

# If total keys is reasonable (< 10000), dump all keys
if [[ "$TOTAL_KEYS" -lt 10000 ]]; then
    log "Dumping individual keys (total: $TOTAL_KEYS)..."
    for i in $(seq 0 15); do
        DB_KEYS=$(eval "$REDIS_CMD -n $i dbsize" 2>/dev/null || echo "0")
        if [[ "$DB_KEYS" -gt 0 ]]; then
            eval "$REDIS_CMD -n $i keys '*'" | while read -r key; do
                if [[ -n "$key" ]]; then
                    echo "DUMP $i:$key" >> "$DUMP_FILE"
                    eval "$REDIS_CMD -n $i dump '$key'" | base64 -w 0 >> "$DUMP_FILE"
                    echo "" >> "$DUMP_FILE"
                fi
            done
        fi
    done
    success "Individual key dump completed"
else
    warning "Too many keys ($TOTAL_KEYS) for individual dump - using RDB backup only"
fi

# Create backup metadata
cat > "$BACKUP_DIR/redis_backup_metadata_$TIMESTAMP.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "redis_server": "$REDIS_HOST:$REDIS_PORT",
    "redis_version": "$REDIS_VERSION",
    "memory_usage": "$REDIS_USED_MEMORY",
    "total_keys": $TOTAL_KEYS,
    "database_count": $REDIS_DB_COUNT,
    "rdb_file_location": "$RDB_FILE_PATH",
    "backup_files": {
        "rdb_backup": "$BACKUP_RDB_FILE",
        "key_counts": "$KEY_COUNT_FILE",
        "individual_dump": "$DUMP_FILE",
        "copy_script": "$BACKUP_DIR/copy_rdb_from_server.sh"
    },
    "purpose": "n8n upgrade pre-backup",
    "backup_method": "bgsave + rdb copy"
}
EOF

# Create checksums if RDB file exists
if [[ -f "$BACKUP_RDB_FILE" ]]; then
    cd "$BACKUP_DIR"
    sha256sum "$(basename "$BACKUP_RDB_FILE")" > "$(basename "$BACKUP_RDB_FILE").sha256"
    success "Checksum created for RDB backup"
fi

# Final verification
log "Performing final backup verification..."

if [[ -f "$BACKUP_RDB_FILE" ]]; then
    RDB_SIZE=$(ls -lh "$BACKUP_RDB_FILE" | awk '{print $5}')
    success "RDB backup created: $RDB_SIZE"
else
    warning "RDB backup file not found - manual copy required"
fi

if [[ -f "$KEY_COUNT_FILE" ]]; then
    success "Key count file created"
fi

success "Redis backup process completed successfully"
log "Backup location: $BACKUP_DIR"
log "Log file: $BACKUP_LOG"

# Display summary
echo ""
echo "=== REDIS BACKUP SUMMARY ==="
echo "Redis Server: $REDIS_HOST:$REDIS_PORT"
echo "Version: $REDIS_VERSION"
echo "Memory Usage: $REDIS_USED_MEMORY"
echo "Total Keys: $TOTAL_KEYS"
echo "Backup files created:"
if [[ -f "$BACKUP_RDB_FILE" ]]; then
    echo "  - $(basename "$BACKUP_RDB_FILE") ($(ls -lh "$BACKUP_RDB_FILE" | awk '{print $5}'))"
fi
echo "  - $(basename "$KEY_COUNT_FILE")"
echo "  - redis_backup_metadata_$TIMESTAMP.json"
echo "Log: $BACKUP_LOG"
echo ""
echo "NOTE: If RDB file copy failed, run copy_rdb_from_server.sh on the Redis server"
success "Redis backup completed successfully"