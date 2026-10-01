#!/bin/bash
# ============================================================
# Ubumwe Connect — Database Backup Script
# Schedule via cron: 0 2 * * * /opt/ubumwe-connect/deployment/scripts/backup.sh
# ============================================================
set -euo pipefail

APP_DIR="/opt/ubumwe-connect"
BACKUP_DIR="/var/backups/ubumwe"
RETENTION_DAYS=30
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/ubumwe_db_$TIMESTAMP.sql.gz"

source "$APP_DIR/.env"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting backup..."
docker compose -f "$APP_DIR/deployment/docker/docker-compose.yml" \
    exec -T postgres \
    pg_dump -U "${DB_USER:-ubumwe_user}" "${DB_NAME:-ubumwe_db}" \
    | gzip > "$BACKUP_FILE"

SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "[$(date)] Backup saved: $BACKUP_FILE ($SIZE)"

# Upload to S3 if configured
if [ -n "${AWS_S3_BUCKET:-}" ]; then
  aws s3 cp "$BACKUP_FILE" "s3://$AWS_S3_BUCKET/backups/$(basename $BACKUP_FILE)" \
    --storage-class STANDARD_IA
  echo "[$(date)] Uploaded to S3: s3://$AWS_S3_BUCKET/backups/"
fi

# Clean up old backups
find "$BACKUP_DIR" -name "ubumwe_db_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
echo "[$(date)] Cleaned up backups older than $RETENTION_DAYS days"

echo "[$(date)] Backup complete."
