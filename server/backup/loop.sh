#!/bin/sh
# Run backup.sh every 24h (first run after ~2 minutes).
set -eu
echo "[backup-loop] started"
sleep 120
while true; do
  /backup.sh || echo "[backup-loop] backup failed ($?)"
  sleep 86400
done
