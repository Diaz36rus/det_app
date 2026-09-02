#!/bin/sh
# Daily Postgres dump for det-app. Keeps last 14 dumps.
set -eu
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION="${RETENTION:-14}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT="$BACKUP_DIR/detapp_${STAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"
echo "[backup] writing $OUT"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$POSTGRES_HOST" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --no-owner --no-acl \
  | gzip -c > "$OUT"

# prune old
ls -1t "$BACKUP_DIR"/detapp_*.sql.gz 2>/dev/null | tail -n +"$((RETENTION + 1))" | while read -r f; do
  rm -f "$f" || true
done

echo "[backup] done ($(du -h "$OUT" | awk '{print $1}'))"
