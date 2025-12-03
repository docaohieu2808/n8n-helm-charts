#!/bin/bash

# PostgreSQL Backup Connection Script
# This script handles secure connection to PostgreSQL HA cluster

# Database Connection Details
PG_HOST="postgres-ha.database.svc.cluster.local"
PG_PORT="5432"
PG_DATABASE="n8n_postgres_db"
PG_USER="n8n_postgres_user"

# Connection timeout settings
PGCONNECTTIMEOUT=30
PGSSLMODE="prefer"

# Set PostgreSQL connection parameters
export PGHOST="$PG_HOST"
export PGPORT="$PG_PORT"
export PGDATABASE="$PG_DATABASE"
export PGUSER="$PG_USER"
export PGCONNECTTIMEOUT="$PGCONNECTTIMEOUT"
export PGSSLMODE="$PGSSLMODE"

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "Error: psql client not found. Please install PostgreSQL client tools."
    exit 1
fi

# Test connection
echo "Testing PostgreSQL connection to $PG_HOST:$PG_PORT..."
if psql -c "SELECT version();" &> /dev/null; then
    echo "PostgreSQL connection successful"
    return 0
else
    echo "Error: Cannot connect to PostgreSQL database"
    echo "Please check:"
    echo "1. Database server is running at $PG_HOST:$PG_PORT"
    echo "2. Network connectivity to database cluster"
    echo "3. User credentials and permissions"
    return 1
fi