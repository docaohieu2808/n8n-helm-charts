# Database Backup Guide for n8n Upgrade

**Backup Date:** 2025-12-03
**Purpose:** Comprehensive database backups before n8n upgrade
**Location:** `/home/hieudc/n8n/backups/251203-2118-pre-upgrade`

## Overview

This directory contains complete backup procedures and scripts for creating and verifying database backups before upgrading n8n. The backup covers both PostgreSQL HA and Redis HA clusters.

## Database Information

### PostgreSQL HA Cluster
- **Server:** `postgres-ha.database.svc.cluster.local:5432`
- **Database:** `n8n_postgres_db`
- **User:** `n8n_postgres_user`
- **Backup Type:** Full database dump (SQL + compressed format)

### Redis HA Cluster
- **Server:** `redis-ha-haproxy.database.svc.cluster.local:6379`
- **Backup Type:** RDB snapshot (BGSAVE) + metadata

## Directory Structure

```
backups/251203-2118-pre-upgrade/
├── postgresql/                          # PostgreSQL backup files
│   ├── backup-connection.sh             # Connection setup script
│   ├── create-backup.sh                 # PostgreSQL backup script
│   ├── backup_instructions.md           # Detailed backup instructions
│   ├── n8n_postgres_backup_*.sql        # SQL backup files
│   ├── n8n_postgres_backup_*.dump       # Compressed backup files
│   ├── backup_metadata_*.json           # Backup metadata
│   └── *.sha256                         # Checksum files
├── redis/                               # Redis backup files
│   ├── redis-backup.sh                  # Redis backup script
│   ├── redis-backup-instructions.md     # Detailed backup instructions
│   ├── redis_backup_*.rdb               # RDB backup files
│   ├── redis_backup_metadata_*.json     # Backup metadata
│   ├── key_count_*.txt                  # Key count information
│   └── *.sha256                         # Checksum files
├── logs/                                # Backup and verification logs
├── verify-backups.sh                    # Backup verification script
├── README.md                            # This file
└── verification_report_*.json           # Verification results
```

## Quick Start Guide

### Step 1: Install Required Tools

```bash
# PostgreSQL client tools
sudo apt update
sudo apt install -y postgresql-client

# Redis client tools
sudo apt install -y redis-tools

# JSON processing (optional, for verification)
sudo apt install -y jq
```

### Step 2: Set Database Credentials

```bash
# PostgreSQL password
export PGPASSWORD="your_postgres_password_here"

# Redis password (if required)
export REDIS_PASSWORD="your_redis_password_here"
```

### Step 3: Run PostgreSQL Backup

```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/postgresql
./create-backup.sh
```

### Step 4: Run Redis Backup

```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/redis
./redis-backup.sh
```

### Step 5: Verify All Backups

```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade
./verify-backups.sh
```

## Backup Validation Checklist

### PostgreSQL Backup ✅
- [ ] SQL backup file created and not empty
- [ ] Compressed dump file created and not empty
- [ ] Metadata JSON file generated
- [ ] SHA256 checksums calculated
- [ ] Backup integrity verified (pg_restore test)
- [ ] Expected database size matches backup size

### Redis Backup ✅
- [ ] RDB file created and not empty
- [ ] Metadata JSON file generated
- [ ] Key count information captured
- [ ] SHA256 checksums calculated
- [ ] RDB file integrity verified
- [ ] Expected memory usage matches backup size

### Overall Validation ✅
- [ ] All backup files present in directory
- [ ] All checksums verified
- [ ] Backup sizes are reasonable
- [ ] Verification script passes
- [ ] Ready for upgrade confirmation

## Emergency Procedures

### If PostgreSQL Backup Fails

1. **Connection Issues:**
   ```bash
   # Test basic connectivity
   telnet postgres-ha.database.svc.cluster.local 5432

   # Test with psql
   psql -h postgres-ha.database.svc.cluster.local -p 5432 -U n8n_postgres_user -d n8n_postgres_db -c "SELECT version();"
   ```

2. **Permission Issues:**
   ```bash
   # Check database permissions
   psql -h postgres-ha.database.svc.cluster.local -p 5432 -U n8n_postgres_user -d n8n_postgres_db -c "\l"
   psql -h postgres-ha.database.svc.cluster.local -p 5432 -U n8n_postgres_user -d n8n_postgres_db -c "\dt"
   ```

3. **Alternative Backup:**
   ```bash
   # Use pg_dumpall for cluster backup
   pg_dumpall -h postgres-ha.database.svc.cluster.local -p 5432 -U n8n_postgres_user > full_cluster_backup.sql
   ```

### If Redis Backup Fails

1. **Connection Issues:**
   ```bash
   # Test basic connectivity
   telnet redis-ha-haproxy.database.svc.cluster.local 6379

   # Test with redis-cli
   redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 ping
   ```

2. **BGSAVE Issues:**
   ```bash
   # Check Redis configuration
   redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 config get save
   redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 config get dir
   redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 config get dbfilename
   ```

3. **Alternative Backup:**
   ```bash
   # Manual RDB copy from Redis server
   # Requires SSH access to Redis server
   ssh redis-server "cat /data/dump.rdb" > redis_backup_manual.rdb
   ```

## Restore Procedures

### PostgreSQL Restore

```bash
# From compressed backup (recommended)
pg_restore \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --verbose \
    --clean \
    --if-exists \
    backup_file.dump

# From SQL backup
psql \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --file=backup_file.sql
```

### Redis Restore

```bash
# Stop Redis server
kubectl scale deployment redis-ha-server --replicas=0 -n database

# Copy backup RDB to Redis data location
kubectl cp redis_backup.rdb redis-pod-name:/data/dump.rdb -n database

# Start Redis server
kubectl scale deployment redis-ha-server --replicas=3 -n database

# Verify data
redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 INFO keyspace
```

## Security Considerations

1. **Access Control:**
   - Backup scripts require database credentials
   - Store credentials securely (environment variables, not in scripts)
   - Restrict access to backup directories

2. **Data Protection:**
   - Backup files contain sensitive data
   - Consider encrypting backup files
   - Store backups in secure, offsite location

3. **Network Security:**
   - Database connections should use TLS when available
   - Monitor network access during backup operations
   - Use VPN or secure tunnels for remote access

## Monitoring and Logging

### Log Files
- PostgreSQL backup logs: `postgresql/backup_*.log`
- Redis backup logs: `redis/redis_backup_*.log`
- Verification logs: `verification_*.log`

### Key Metrics to Monitor
- Database connection latency
- Backup duration
- Backup file sizes
- CPU and memory usage during backup
- Network throughput during large backup transfers

## Troubleshooting

### Common Issues

1. **Timeout Errors:**
   - Increase connection timeout values
   - Check network latency to database servers
   - Monitor system resources during backup

2. **Permission Errors:**
   - Verify database user permissions
   - Check file system permissions for backup directory
   - Ensure sufficient disk space

3. **Large Backup Sizes:**
   - Consider compression levels
   - Monitor available disk space
   - Plan for backup storage requirements

4. **Network Connectivity:**
   - Verify DNS resolution of database hostnames
   - Check firewall rules
   - Test with basic connectivity tools

## Post-Backup Actions

### Before Upgrade
1. Store backup copies in multiple locations
2. Test restore procedures in staging environment
3. Document backup retention schedule
4. Notify stakeholders of backup completion

### After Upgrade
1. Verify database connectivity and data integrity
2. Monitor application performance
3. Update backup procedures if schema changes occurred
4. Schedule regular backup tests

## Contact Information

For backup-related issues, contact:
- Database Administrator: [Contact Information]
- Infrastructure Team: [Contact Information]
- Application Team: [Contact Information]

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-03 | Initial backup procedures for n8n upgrade |

---

**Important:** Do not proceed with the n8n upgrade until all backup verification steps have been completed successfully and you have confirmed backup integrity.