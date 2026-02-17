FROM python:3.12-slim

# Prevent .pyc files and force unbuffered stdout/stderr for container logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# --- Dependencies first for layer caching ---
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Application code ---
COPY app/ app/

# --- Non-root user (AKS / K8s security best practice) ---
RUN addgroup --system app && adduser --system --ingroup app app
USER app

EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
