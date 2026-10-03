#!/bin/sh
# Daily Postgres dump for det-app. Keeps last $RETENTION dumps.
set -eu
set -o pipefail
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION="${RETENTION:-14}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT="$BACKUP_DIR/detapp_${STAMP}.sql.gz"
TMP="$OUT.partial"

mkdir -p "$BACKUP_DIR"
echo "[backup] writing $OUT"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$POSTGRES_HOST" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --no-owner --no-acl \
  | gzip -c > "$TMP"

gzip -t "$TMP"
mv "$TMP" "$OUT"
chmod 600 "$OUT"

# prune old
ls -1t "$BACKUP_DIR"/detapp_*.sql.gz 2>/dev/null | tail -n +"$((RETENTION + 1))" | while read -r f; do
  rm -f "$f" || true
done
rm -f "$BACKUP_DIR"/*.partial 2>/dev/null || true

echo "[backup] done ($(du -h "$OUT" | awk '{print $1}'))"
