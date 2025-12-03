#!/bin/bash

# Backup Verification Script for n8n Upgrade
# Verifies integrity and completeness of PostgreSQL and Redis backups

set -euo pipefail

# Configuration
BACKUP_DIR="/home/hieudc/n8n/backups/251203-2118-pre-upgrade"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
VERIFICATION_LOG="$BACKUP_DIR/verification_$TIMESTAMP.log"
POSTGRES_DIR="$BACKUP_DIR/postgresql"
REDIS_DIR="$BACKUP_DIR/redis"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verification results
POSTGRES_STATUS="FAILED"
REDIS_STATUS="FAILED"
OVERALL_STATUS="PASSED"

# Logging function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$VERIFICATION_LOG"
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

# Info message
info() {
    log "${BLUE}INFO: $1${NC}"
}

# Header function
header() {
    echo ""
    echo "${BLUE}=== $1 ===${NC}"
    log "$1"
}

# Start verification process
log "Starting comprehensive backup verification for n8n upgrade"
log "Backup directory: $BACKUP_DIR"
log "Verification log: $VERIFICATION_LOG"

# Check if backup directories exist
header "CHECKING BACKUP DIRECTORY STRUCTURE"

if [[ ! -d "$BACKUP_DIR" ]]; then
    error_exit "Backup directory does not exist: $BACKUP_DIR"
fi

if [[ ! -d "$POSTGRES_DIR" ]]; then
    error_exit "PostgreSQL backup directory does not exist: $POSTGRES_DIR"
fi

if [[ ! -d "$REDIS_DIR" ]]; then
    error_exit "Redis backup directory does not exist: $REDIS_DIR"
fi

success "All backup directories found"

# PostgreSQL Backup Verification
header "POSTGRESQL BACKUP VERIFICATION"

POSTGRES_FILES_FOUND=0
POSTGRES_FILES_EXPECTED=3  # SQL dump, compressed dump, metadata

# Check for PostgreSQL backup files
echo "Checking PostgreSQL backup files..."

# Check SQL backup
SQL_FILES=($(find "$POSTGRES_DIR" -name "*.sql" -type f 2>/dev/null))
if [[ ${#SQL_FILES[@]} -gt 0 ]]; then
    POSTGRES_FILES_FOUND=$((POSTGRES_FILES_FOUND + 1))
    LATEST_SQL=$(printf '%s\n' "${SQL_FILES[@]}" | xargs ls -t | head -n 1)
    SQL_SIZE=$(ls -lh "$LATEST_SQL" | awk '{print $5}')
    info "SQL backup found: $(basename "$LATEST_SQL") ($SQL_SIZE)"

    # Verify SQL file is not empty and has valid content
    if [[ -s "$LATEST_SQL" ]]; then
        # Check for basic PostgreSQL dump indicators
        if grep -q "PostgreSQL database dump" "$LATEST_SQL" 2>/dev/null || \
           grep -q "CREATE TABLE" "$LATEST_SQL" 2>/dev/null || \
           grep -q "COPY" "$LATEST_SQL" 2>/dev/null; then
            success "SQL backup content verified"
        else
            warning "SQL backup content may be incomplete"
        fi
    else
        error_exit "SQL backup file is empty"
    fi
else
    warning "No SQL backup files found"
fi

# Check compressed backup
DUMP_FILES=($(find "$POSTGRES_DIR" -name "*.dump" -type f 2>/dev/null))
if [[ ${#DUMP_FILES[@]} -gt 0 ]]; then
    POSTGRES_FILES_FOUND=$((POSTGRES_FILES_FOUND + 1))
    LATEST_DUMP=$(printf '%s\n' "${DUMP_FILES[@]}" | xargs ls -t | head -n 1)
    DUMP_SIZE=$(ls -lh "$LATEST_DUMP" | awk '{print $5}')
    info "Compressed backup found: $(basename "$LATEST_DUMP") ($DUMP_SIZE)"

    # Verify dump file integrity (basic check)
    if command -v pg_restore >/dev/null 2>&1; then
        if pg_restore --list "$LATEST_DUMP" >/dev/null 2>&1; then
            success "Compressed backup integrity verified"
        else
            warning "Compressed backup integrity check failed"
        fi
    else
        warning "pg_restore not available for integrity check"
    fi
else
    warning "No compressed backup files found"
fi

# Check metadata files
METADATA_FILES=($(find "$POSTGRES_DIR" -name "backup_metadata_*.json" -type f 2>/dev/null))
if [[ ${#METADATA_FILES[@]} -gt 0 ]]; then
    POSTGRES_FILES_FOUND=$((POSTGRES_FILES_FOUND + 1))
    LATEST_METADATA=$(printf '%s\n' "${METADATA_FILES[@]}" | xargs ls -t | head -n 1)
    info "Metadata file found: $(basename "$LATEST_METADATA")"

    # Validate metadata JSON
    if command -v jq >/dev/null 2>&1; then
        if jq . "$LATEST_METADATA" >/dev/null 2>&1; then
            success "Metadata JSON validation passed"

            # Extract key information from metadata
            DB_NAME=$(jq -r '.database' "$LATEST_METADATA" 2>/dev/null || echo "unknown")
            BACKUP_DATE=$(jq -r '.timestamp' "$LATEST_METADATA" 2>/dev/null || echo "unknown")
            info "Database: $DB_NAME, Backup date: $BACKUP_DATE"
        else
            warning "Metadata JSON validation failed"
        fi
    else
        warning "jq not available for metadata validation"
    fi
else
    warning "No metadata files found"
fi

# Check checksum files
CHECKSUM_FILES=($(find "$POSTGRES_DIR" -name "*.sha256" -type f 2>/dev/null))
if [[ ${#CHECKSUM_FILES[@]} -gt 0 ]]; then
    info "Checksum files found: ${#CHECKSUM_FILES[@]}"

    # Verify checksums if sha256sum is available
    if command -v sha256sum >/dev/null 2>&1; then
        CHECKSUM_PASSED=0
        for checksum_file in "${CHECKSUM_FILES[@]}"; do
            if sha256sum -c "$checksum_file" >/dev/null 2>&1; then
                CHECKSUM_PASSED=$((CHECKSUM_PASSED + 1))
            fi
        done

        if [[ $CHECKSUM_PASSED -eq ${#CHECKSUM_FILES[@]} ]]; then
            success "All checksums verified"
        else
            warning "Some checksums failed verification"
        fi
    else
        warning "sha256sum not available for checksum verification"
    fi
fi

# Evaluate PostgreSQL backup status
if [[ $POSTGRES_FILES_FOUND -ge 2 ]]; then
    POSTGRES_STATUS="PASSED"
    success "PostgreSQL backup verification: $POSTGRES_FILES_FOUND/$POSTGRES_FILES_EXPECTED files found"
else
    error_exit "PostgreSQL backup verification failed: Only $POSTGRES_FILES_FOUND/$POSTGRES_FILES_EXPECTED files found"
fi

# Redis Backup Verification
header "REDIS BACKUP VERIFICATION"

REDIS_FILES_FOUND=0
REDIS_FILES_EXPECTED=2  # RDB file, metadata

# Check for Redis backup files
echo "Checking Redis backup files..."

# Check RDB files
RDB_FILES=($(find "$REDIS_DIR" -name "*.rdb" -type f 2>/dev/null))
if [[ ${#RDB_FILES[@]} -gt 0 ]]; then
    REDIS_FILES_FOUND=$((REDIS_FILES_FOUND + 1))
    LATEST_RDB=$(printf '%s\n' "${RDB_FILES[@]}" | xargs ls -t | head -n 1)
    RDB_SIZE=$(ls -lh "$LATEST_RDB" | awk '{print $5}')
    info "RDB backup found: $(basename "$LATEST_RDB") ($RDB_SIZE)"

    # Verify RDB file integrity
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli --rdb "$LATEST_RDB" >/dev/null 2>&1; then
            success "RDB backup integrity verified"
        else
            warning "RDB backup integrity check failed"
        fi
    else
        warning "redis-cli not available for RDB integrity check"
    fi

    # Check RDB file header
    if [[ $(head -c 9 "$LATEST_RDB") == "REDIS" ]]; then
        success "RDB file header is valid"
    else
        warning "RDB file header appears invalid"
    fi
else
    warning "No RDB backup files found"
fi

# Check Redis metadata files
REDIS_METADATA_FILES=($(find "$REDIS_DIR" -name "redis_backup_metadata_*.json" -type f 2>/dev/null))
if [[ ${#REDIS_METADATA_FILES[@]} -gt 0 ]]; then
    REDIS_FILES_FOUND=$((REDIS_FILES_FOUND + 1))
    LATEST_REDIS_METADATA=$(printf '%s\n' "${REDIS_METADATA_FILES[@]}" | xargs ls -t | head -n 1)
    info "Redis metadata file found: $(basename "$LATEST_REDIS_METADATA")"

    # Validate metadata JSON
    if command -v jq >/dev/null 2>&1; then
        if jq . "$LATEST_REDIS_METADATA" >/dev/null 2>&1; then
            success "Redis metadata JSON validation passed"

            # Extract key information from metadata
            REDIS_VERSION=$(jq -r '.redis_version' "$LATEST_REDIS_METADATA" 2>/dev/null || echo "unknown")
            TOTAL_KEYS=$(jq -r '.total_keys' "$LATEST_REDIS_METADATA" 2>/dev/null || echo "unknown")
            MEMORY_USAGE=$(jq -r '.memory_usage' "$LATEST_REDIS_METADATA" 2>/dev/null || echo "unknown")
            info "Redis version: $REDIS_VERSION, Keys: $TOTAL_KEYS, Memory: $MEMORY_USAGE"
        else
            warning "Redis metadata JSON validation failed"
        fi
    else
        warning "jq not available for Redis metadata validation"
    fi
else
    warning "No Redis metadata files found"
fi

# Check for additional Redis backup files
KEY_COUNT_FILES=($(find "$REDIS_DIR" -name "key_count_*.txt" -type f 2>/dev/null))
DUMP_FILES=($(find "$REDIS_DIR" -name "redis_dump_*.txt" -type f 2>/dev/null))
COPY_SCRIPTS=($(find "$REDIS_DIR" -name "copy_rdb_from_server.sh" -type f 2>/dev/null))

if [[ ${#KEY_COUNT_FILES[@]} -gt 0 ]]; then
    info "Key count files found: ${#KEY_COUNT_FILES[@]}"
fi

if [[ ${#DUMP_FILES[@]} -gt 0 ]]; then
    info "Individual dump files found: ${#DUMP_FILES[@]}"
fi

if [[ ${#COPY_SCRIPTS[@]} -gt 0 ]]; then
    info "Copy scripts found: ${#COPY_SCRIPTS[@]}"
fi

# Evaluate Redis backup status
if [[ $REDIS_FILES_FOUND -ge 1 ]]; then
    REDIS_STATUS="PASSED"
    success "Redis backup verification: $REDIS_FILES_FOUND/$REDIS_FILES_EXPECTED files found"
else
    warning "Redis backup verification incomplete: Only $REDIS_FILES_FOUND/$REDIS_FILES_EXPECTED files found"
    REDIS_STATUS="PARTIAL"
fi

# Check Redis checksums
REDIS_CHECKSUM_FILES=($(find "$REDIS_DIR" -name "*.sha256" -type f 2>/dev/null))
if [[ ${#REDIS_CHECKSUM_FILES[@]} -gt 0 ]]; then
    info "Redis checksum files found: ${#REDIS_CHECKSUM_FILES[@]}"
fi

# Overall Assessment
header "OVERALL BACKUP ASSESSMENT"

# Calculate total backup sizes
POSTGRES_TOTAL_SIZE=$(du -sh "$POSTGRES_DIR" 2>/dev/null | cut -f1 || echo "unknown")
REDIS_TOTAL_SIZE=$(du -sh "$REDIS_DIR" 2>/dev/null | cut -f1 || echo "unknown")
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")

info "PostgreSQL backup size: $POSTGRES_TOTAL_SIZE"
info "Redis backup size: $REDIS_TOTAL_SIZE"
info "Total backup size: $TOTAL_SIZE"

# Evaluate overall status
if [[ "$POSTGRES_STATUS" == "PASSED" && "$REDIS_STATUS" == "PASSED" ]]; then
    OVERALL_STATUS="PASSED"
    success "All backups verified successfully - Ready for upgrade"
elif [[ "$POSTGRES_STATUS" == "PASSED" && "$REDIS_STATUS" == "PARTIAL" ]]; then
    OVERALL_STATUS="PARTIAL"
    warning "PostgreSQL backup verified, Redis backup partial - Proceed with caution"
else
    OVERALL_STATUS="FAILED"
    error_exit "Critical backup verification failed - Do not proceed with upgrade"
fi

# Generate verification report
VERIFICATION_REPORT="$BACKUP_DIR/verification_report_$TIMESTAMP.json"

cat > "$VERIFICATION_REPORT" << EOF
{
    "verification_timestamp": "$(date -Iseconds)",
    "backup_directory": "$BACKUP_DIR",
    "postgresql": {
        "status": "$POSTGRES_STATUS",
        "files_found": $POSTGRES_FILES_FOUND,
        "files_expected": $POSTGRES_FILES_EXPECTED,
        "total_size": "$POSTGRES_TOTAL_SIZE",
        "sql_files": ${#SQL_FILES[@]},
        "dump_files": ${#DUMP_FILES[@]},
        "metadata_files": ${#METADATA_FILES[@]},
        "checksum_files": ${#CHECKSUM_FILES[@]}
    },
    "redis": {
        "status": "$REDIS_STATUS",
        "files_found": $REDIS_FILES_FOUND,
        "files_expected": $REDIS_FILES_EXPECTED,
        "total_size": "$REDIS_TOTAL_SIZE",
        "rdb_files": ${#RDB_FILES[@]},
        "metadata_files": ${#REDIS_METADATA_FILES[@]},
        "key_count_files": ${#KEY_COUNT_FILES[@]},
        "dump_files": ${#DUMP_FILES[@]},
        "copy_scripts": ${#COPY_SCRIPTS[@]},
        "checksum_files": ${#REDIS_CHECKSUM_FILES[@]}
    },
    "overall_status": "$OVERALL_STATUS",
    "total_backup_size": "$TOTAL_SIZE",
    "verification_log": "$VERIFICATION_LOG",
    "ready_for_upgrade": $([ "$OVERALL_STATUS" == "PASSED" ] && echo "true" || echo "false")
}
EOF

# Final Summary
header "VERIFICATION SUMMARY"

echo "PostgreSQL Backup: $POSTGRES_STATUS ($POSTGRES_FILES_FOUND/$POSTGRES_FILES_EXPECTED files)"
echo "Redis Backup: $REDIS_STATUS ($REDIS_FILES_FOUND/$REDIS_FILES_EXPECTED files)"
echo "Overall Status: $OVERALL_STATUS"
echo "Total Size: $TOTAL_SIZE"
echo ""

if [[ "$OVERALL_STATUS" == "PASSED" ]]; then
    success "All backups verified successfully - Ready for n8n upgrade"
    echo ""
    echo "Next steps:"
    echo "1. Store backup directory in a secure location"
    echo "2. Test restore process in a staging environment"
    echo "3. Proceed with n8n upgrade"
elif [[ "$OVERALL_STATUS" == "PARTIAL" ]]; then
    warning "Some backups may be incomplete - Review before proceeding"
    echo ""
    echo "Recommended actions:"
    echo "1. Complete missing backups manually"
    echo "2. Re-run verification"
    echo "3. Proceed with caution"
else
    error_exit "Backup verification failed - Address issues before upgrade"
fi

echo ""
echo "Files created:"
echo "- Verification log: $VERIFICATION_LOG"
echo "- Verification report: $VERIFICATION_REPORT"
echo ""

exit $([ "$OVERALL_STATUS" == "PASSED" ] && echo 0 || echo 1)