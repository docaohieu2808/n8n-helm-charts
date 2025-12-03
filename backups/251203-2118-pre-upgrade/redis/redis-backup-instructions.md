# Redis Backup Instructions for n8n Upgrade

## Prerequisites

Before running the backup, ensure you have:

1. **Redis Client Tools**: Install `redis-tools` package
   ```bash
   sudo apt update
   sudo apt install -y redis-tools
   ```

2. **Network Access**: Ensure connectivity to `redis-ha-haproxy.database.svc.cluster.local:6379`

3. **Redis Access**: Ensure you have appropriate permissions to run BGSAVE

## Quick Backup Execution

### Step 1: Set Environment Variables (if password required)
```bash
export REDIS_PASSWORD="your_redis_password_here"
```

### Step 2: Run Backup Script
```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/redis
./redis-backup.sh
```

### Step 3: Verify Backup
```bash
# Check backup files
ls -la *.rdb* *.json *.txt *.sha256

# Verify RDB file integrity (if available)
redis-cli --rdb backup_file.rdb
```

## Manual Backup Commands

If the script fails, use these manual commands:

### Method 1: BGSAVE + RDB Copy (Recommended)
```bash
# Connect to Redis
redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379

# Inside Redis CLI
AUTH your_password_here  # if required
INFO server              # check Redis info
LASTSAVE                 # get last save timestamp
BGSAVE                   # trigger background save
LASTSAVE                 # verify new save timestamp

# Get RDB file location
CONFIG GET dir
CONFIG GET dbfilename
```

### Method 2: Direct RDB Dump (Redis 6.2+)
```bash
redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 \
    --rdb redis_backup_$(date +%Y%m%d_%H%M%S).rdb
```

### Method 3: Key-by-Key Backup (small datasets)
```bash
#!/bin/bash
REDIS_HOST="redis-ha-haproxy.database.svc.cluster.local"
REDIS_PORT="6379"
BACKUP_FILE="redis_keys_$(date +%Y%m%d_%H%M%S).txt"

for db in {0..15}; do
    keys=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $db keys "*" 2>/dev/null)
    if [[ -n "$keys" ]]; then
        echo "Database $db:" >> $BACKUP_FILE
        echo "$keys" | while read key; do
            if [[ -n "$key" ]]; then
                echo "Key: $key" >> $BACKUP_FILE
                redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $db get "$key" >> $BACKUP_FILE
                echo "---" >> $BACKUP_FILE
            fi
        done
    fi
done
```

## RDB File Copy Methods

### Method 1: Copy from Redis Server (if SSH access)
```bash
# On Redis server
REDIS_DIR=$(redis-cli config get dir | tail -n 1)
REDIS_DBFILE=$(redis-cli config get dbfilename | tail -n 1)
scp "$REDIS_DIR/$REDIS_DBFILE" user@backup-server:/backup/location/
```

### Method 2: Use Kubernetes Port Forwarding
```bash
# Port forward to Redis pod
kubectl port-forward service/redis-ha-haproxy 6379:6379 -n database

# Run backup script locally
./redis-backup.sh
```

### Method 3: Copy from Pod (if running in Kubernetes)
```bash
# Find Redis pod
kubectl get pods -n database | grep redis

# Copy RDB from pod
kubectl exec -n database <redis-pod-name> -- \
    cat /data/dump.rdb > redis_backup_$(date +%Y%m%d_%H%M%S).rdb
```

## Restore Instructions (if needed)

### Method 1: RDB Restore
```bash
# Stop Redis server
sudo systemctl stop redis-server

# Backup current RDB file
sudo cp /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.backup

# Copy backup RDB file
sudo cp redis_backup_file.rdb /var/lib/redis/dump.rdb

# Set correct permissions
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo chmod 640 /var/lib/redis/dump.rdb

# Start Redis server
sudo systemctl start redis-server

# Verify data
redis-cli INFO memory
redis-cli DBSIZE
```

### Method 2: Redis CLI Restore (from key dump)
```bash
#!/bin/bash
# Restore from key dump file created by backup script

BACKUP_FILE="redis_keys_backup.txt"
REDIS_HOST="localhost"
REDIS_PORT="6379"

while IFS= read -r line; do
    if [[ "$line" =~ ^Key: ]]; then
        key=$(echo "$line" | cut -d' ' -f2-)
        read -r value
        if [[ "$value" != "---" && -n "$key" ]]; then
            redis-cli -h $REDIS_HOST -p $REDIS_PORT set "$key" "$value"
        fi
    fi
done < "$BACKUP_FILE"
```

## Troubleshooting

### Connection Issues
1. **Timeout**: Check network connectivity with `telnet redis-ha-haproxy.database.svc.cluster.local 6379`
2. **Authentication**: Verify password and AUTH command
3. **Network Policies**: Ensure no firewall rules block Redis access

### BGSAVE Issues
1. **Permission Denied**: Ensure Redis has write permissions to its data directory
2. **Disk Space**: Check available disk space (needs ~2x memory size)
3. **Fork Error**: May need to disable `save` config temporarily

### RDB File Issues
1. **File Not Found**: Check Redis config for correct `dir` and `dbfilename`
2. **Corruption**: Verify RDB file with `redis-cli --rdb file.rdb`
3. **Permissions**: Ensure you can read the RDB file from Redis server

### Large Datasets
1. **Memory Usage**: BGSAVE requires additional memory for fork
2. **Network Transfer**: Large RDB files may take time to copy
3. **Storage Space**: Ensure backup location has sufficient space

## Backup Verification

After backup creation, verify:

1. **File Size**: Should be proportional to Redis memory usage
2. **Key Count**: Compare with `INFO keyspace` output
3. **RDB Integrity**: Run `redis-cli --rdb backup_file.rdb > /dev/null`
4. **Checksum**: Verify SHA256 checksums match
5. **Sample Data**: Test restore of a few keys to ensure data integrity