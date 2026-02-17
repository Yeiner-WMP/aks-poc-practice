# AKS PoC — Python Web Service

Minimal, production-ready FastAPI service with a styled landing page and Kubernetes health check, containerized for AKS deployment.

## Project Structure

```
aks-poc-practice/
├── app/
│   ├── __init__.py
│   └── main.py            # Application entrypoint (routes, middleware, template)
├── Dockerfile              # Production container (python:3.12-slim, non-root)
├── .dockerignore
├── .gitignore
├── requirements.txt
└── README.md
```

## Quick Start

### Local development

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

### Docker

```bash
docker build -t aks-poc .
docker run --rm -p 8080:8080 aks-poc
```

Then open [http://localhost:8080](http://localhost:8080).

## API Reference

| Method | Path       | Content-Type               | Description                        |
|--------|------------|----------------------------|------------------------------------|
| GET    | `/`        | `text/html; charset=utf-8` | Styled landing page with server info |
| GET    | `/healthz` | `application/json`         | `{"status":"ok"}` — K8s probe target |

## Configuration

| Variable | Default | Description        |
|----------|---------|--------------------|
| `PORT`   | `8080`  | Server listen port |

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| **FastAPI + Uvicorn** | Async-ready, high performance, minimal boilerplate |
| **Inline HTML/CSS** | Zero external dependencies — renders offline, single-request load |
| **`_render_page()` as pure function** | Separates template logic from route handling; trivially testable |
| **HTTP middleware for logging** | Captures every request method + path + status without touching route code |
| **No Swagger UI** | `docs_url=None` reduces attack surface in production |
| **Non-root container user** | Required by AKS pod security standards and general best practice |
| **Dependency layer caching** | `requirements.txt` copied before app code — rebuilds only when deps change |

## Container Security

The Dockerfile follows container hardening best practices:

- Base image: `python:3.12-slim` (minimal attack surface)
- Runs as system user `app` (non-root, no login shell)
- No `.pyc` generation (`PYTHONDONTWRITEBYTECODE=1`)
- Unbuffered output (`PYTHONUNBUFFERED=1`) for reliable container logging
- Compatible with Kubernetes `runAsNonRoot: true` without modification

## Kubernetes Usage

Point liveness and readiness probes at the health endpoint:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 3
  periodSeconds: 5
```
