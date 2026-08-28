#!/bin/bash
set -euo pipefail
rm -rf /opt/det-app/website
mkdir -p /opt/det-app/website
if [ -d /tmp/det-website-upload-src/website ]; then
  cp -a /tmp/det-website-upload-src/website/. /opt/det-app/website/
else
  cp -a /tmp/det-website-upload-src/. /opt/det-app/website/
fi
rm -rf /tmp/det-website-upload-src /tmp/det-website-upload
cd /opt/det-app
docker compose up -d --force-recreate caddy
sleep 1
docker compose exec -T caddy ls -la /srv/website | head
