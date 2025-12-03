# Quick Start: Database Backups for n8n Upgrade

## 🚀 5-Minute Backup Guide

**⚠️ WARNING: This is a critical operation. Do not proceed with upgrade until backups are verified.**

### Prerequisites (1 minute)

```bash
# Install required tools
sudo apt update && sudo apt install -y postgresql-client redis-tools jq

# Set your database credentials
export PGPASSWORD="your_postgres_password_here"
export REDIS_PASSWORD="your_redis_password_here"  # if required
```

### Run Backups (2 minutes)

```bash
# PostgreSQL Backup
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/postgresql
./create-backup.sh

# Redis Backup
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade/redis
./redis-backup.sh
```

### Verify Backups (1 minute)

```bash
cd /home/hieudc/n8n/backups/251203-2118-pre-upgrade
./verify-backups.sh
```

### Check Results (1 minute)

After verification runs, look for this output:
```
=== OVERALL BACKUP ASSESSMENT ===
✅ All backups verified successfully - Ready for n8n upgrade
```

If you see ✅ SUCCESS - you're ready for the upgrade!
If you see ⚠️ WARNING or ❌ ERROR - address issues first.

## 📋 Manual Commands (if scripts fail)

### PostgreSQL
```bash
pg_dump -h postgres-ha.database.svc.cluster.local -p 5432 \
    -U n8n_postgres_user -d n8n_postgres_db \
    --format=custom --compress=9 \
    --file=postgres_backup_$(date +%Y%m%d_%H%M%S).dump
```

### Redis
```bash
redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 \
    --rdb redis_backup_$(date +%Y%m%d_%H%M%S).rdb
```

## 🔧 Quick Troubleshooting

### Connection Issues
```bash
# Test PostgreSQL
psql -h postgres-ha.database.svc.cluster.local -p 5432 \
    -U n8n_postgres_user -d n8n_postgres_db -c "SELECT 1;"

# Test Redis
redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 ping
```

### Permission Issues
```bash
# Make scripts executable
chmod +x /home/hieudc/n8n/backups/251203-2118-pre-upgrade/*/*.sh

# Check backup directory permissions
ls -la /home/hieudc/n8n/backups/251203-2118-pre-upgrade/
```

## 📊 What Gets Backed Up

| Database | Size | Format | Files Created |
|----------|------|--------|---------------|
| PostgreSQL | Database size | SQL + Compressed | .sql, .dump, .json, .sha256 |
| Redis | Memory usage | RDB snapshot | .rdb, .json, .txt, .sha256 |

## ✅ Success Indicators

- ✅ All scripts run without errors
- ✅ Backup files are created (not 0 bytes)
- ✅ Verification script reports "PASSED"
- ✅ Checksum files validate successfully

## ❌ Failure Indicators

- ❌ Script returns error codes
- ❌ Empty backup files
- ❌ Connection timeout errors
- ❌ Permission denied errors
- ❌ Verification reports "FAILED"

## 🆘 Get Help

If you encounter issues:

1. Check the detailed logs in each subdirectory
2. Review the full documentation: `/home/hieudc/n8n/backups/251203-2118-pre-upgrade/README.md`
3. Test connectivity manually using the commands above
4. Contact your database administrator

## ⏱️ Time Estimates

- **Small database (<1GB):** 2-3 minutes total
- **Medium database (1-10GB):** 5-10 minutes total
- **Large database (>10GB):** 15-30 minutes total

## 🎯 Next Steps After Backup

1. ✅ Copy backup directory to a secure offsite location
2. ✅ Test restore in a staging environment (recommended)
3. ✅ Proceed with n8n upgrade
4. ✅ Monitor application after upgrade

---

**Remember:** Backups are your safety net. Take the time to verify them properly before proceeding with any upgrade.