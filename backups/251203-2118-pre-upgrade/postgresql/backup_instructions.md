# PostgreSQL Backup Instructions for n8n Upgrade

## Prerequisites

Before running the backup, ensure you have:

1. **PostgreSQL Client Tools**: Install `postgresql-client` package
   ```bash
   sudo apt update
   sudo apt install -y postgresql-client
   ```

2. **Database Credentials**: You'll need the password for `n8n_postgres_user`

3. **Network Access**: Ensure connectivity to `postgres-ha.database.svc.cluster.local:5432`

## Quick Backup Execution

### Step 1: Set Environment Variables
```bash
export PGPASSWORD="your_postgres_password_here"
export PGHOST="postgres-ha.database.svc.cluster.local"
export PGPORT="5432"
export PGDATABASE="n8n_postgres_db"
export PGUSER="n8n_postgres_user"
export PGCONNECTTIMEOUT="30"
```

### Step 2: Run Backup Script
```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/postgresql
./create-backup.sh
```

### Step 3: Verify Backup
```bash
# Check backup files
ls -la *.sql* *.dump* *.json *.sha256

# Verify backup integrity
sha256sum -c *.sha256
```

## Manual Backup Commands

If the script fails, use these manual commands:

### Compressed Backup (Recommended)
```bash
pg_dump \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --format=custom \
    --compress=9 \
    --file=backup_$(date +%Y%m%d_%H%M%S).dump
```

### SQL Backup (for compatibility)
```bash
pg_dump \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --format=plain \
    --encoding=UTF8 \
    --file=backup_$(date +%Y%m%d_%H%M%S).sql
```

## Restore Instructions (if needed)

### From Compressed Backup
```bash
pg_restore \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --verbose \
    --clean \
    --if-exists \
    backup_file.dump
```

### From SQL Backup
```bash
psql \
    --host=postgres-ha.database.svc.cluster.local \
    --port=5432 \
    --username=n8n_postgres_user \
    --dbname=n8n_postgres_db \
    --file=backup_file.sql
```

## Troubleshooting

### Connection Issues
1. **Timeout**: Increase `PGCONNECTTIMEOUT` value
2. **Network**: Check connectivity with `telnet postgres-ha.database.svc.cluster.local 5432`
3. **Credentials**: Verify username and password

### Permission Issues
1. **Read Access**: Ensure user has SELECT permissions on all tables
2. **Write Access**: Ensure backup directory is writable
3. **Database Access**: Verify user can connect to the database

### Backup Size
1. **Large Databases**: Consider using `--jobs=N` for parallel backup
2. **Storage**: Ensure sufficient disk space (typically 2-3x database size)
3. **Compression**: Use compression level 6-9 for space efficiency

## Backup Verification

After backup creation, verify:

1. **File Size**: Should be proportional to database size
2. **Integrity**: Run `pg_restore --list backup_file.dump`
3. **Checksum**: Verify SHA256 checksums match
4. **Content**: Check that backup contains expected tables and data