FROM python:3.12-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# uid 10001 совпадает с chown releases_data в tools/deploy_api_files.ps1.
RUN useradd --system --uid 10001 --no-create-home detapi \
    && mkdir -p /data/releases \
    && chown -R detapi:detapi /data/releases
USER detapi

EXPOSE 8000
# Порт 8000 не публикуется наружу — X-Forwarded-For приходит только от Caddy.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
