#!/bin/bash
# Вставить целиком в консоль Selectel (root@cali)
set -e
mkdir -p /opt/det-app/api/app
cd /opt/det-app

cat > docker-compose.yml <<'EOF'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: detapp
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: detapp
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U detapp -d detapp"]
      interval: 5s
      timeout: 5s
      retries: 10

  api:
    build: ./api
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql+psycopg://detapp:${POSTGRES_PASSWORD}@db:5432/detapp
      APP_ENV: production
    depends_on:
      db:
        condition: service_healthy

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - api

volumes:
  pgdata:
  caddy_data:
  caddy_config:
EOF

cat > Caddyfile <<'EOF'
:80 {
	reverse_proxy api:8000
}
EOF

cat > api/Dockerfile <<'EOF'
FROM python:3.12-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

cat > api/requirements.txt <<'EOF'
fastapi==0.115.6
uvicorn[standard]==0.32.1
psycopg[binary]==2.9.10
sqlalchemy==2.0.36
pydantic-settings==2.6.1
EOF

cat > api/app/__init__.py <<'EOF'
EOF

cat > api/app/main.py <<'EOF'
from fastapi import FastAPI

app = FastAPI(title="Det App API", version="0.1.0")


@app.get("/health")
def health():
    return {"ok": True, "service": "det-app-api"}


@app.get("/")
def root():
    return {"name": "Det App API", "docs": "/docs"}
EOF

if [ ! -f .env ]; then
  echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" > .env
fi

echo "OK: files ready in /opt/det-app"
ls -la
ls -la api api/app
echo "---- .env (сохрани пароль у себя) ----"
cat .env
