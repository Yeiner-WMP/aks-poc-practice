"""FastAPI web service for AKS deployment.

Provides a styled landing page and a health-check endpoint.
Binds to 0.0.0.0 on the port specified by the PORT env var (default 8080).
"""

import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse

# ---------------------------------------------------------------------------
# Logging — configured once at module level
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("app")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PORT: int = int(os.getenv("PORT", "8080"))

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------
app = FastAPI(title="AKS PoC", docs_url=None, redoc_url=None)


# ---------------------------------------------------------------------------
# Middleware — request logging
# ---------------------------------------------------------------------------
@app.middleware("http")
async def log_requests(request: Request, call_next) -> Response:
    """Log every inbound request's method and path."""
    response: Response = await call_next(request)
    logger.info("%s %s → %s", request.method, request.url.path, response.status_code)
    return response


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
def root() -> str:
    """Return a styled HTML landing page with greeting, time, and port."""
    now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    return _render_page(server_time=now_utc, port=PORT)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness / readiness probe for Kubernetes."""
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
def _on_startup() -> None:
    logger.info("Listening on http://0.0.0.0:%s/", PORT)


# ---------------------------------------------------------------------------
# Template
# ---------------------------------------------------------------------------
def _render_page(*, server_time: str, port: int) -> str:
    """Build the HTML landing page. Pure function, easy to test."""
    return f"""\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AKS PoC</title>
  <style>
    *,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}

    body{{
      min-height:100vh;
      display:flex;
      align-items:center;
      justify-content:center;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,
                   "Helvetica Neue",Arial,sans-serif;
      background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);
      color:#e2e8f0;
      padding:1rem;
    }}

    .card{{
      background:rgba(255,255,255,.06);
      backdrop-filter:blur(12px);
      border:1px solid rgba(255,255,255,.10);
      border-radius:1.25rem;
      padding:3rem 3.5rem;
      max-width:480px;
      width:100%;
      text-align:center;
      box-shadow:0 8px 32px rgba(0,0,0,.35);
    }}

    .badge{{
      display:inline-block;
      font-size:.7rem;
      font-weight:600;
      letter-spacing:.08em;
      text-transform:uppercase;
      background:rgba(99,102,241,.25);
      color:#a5b4fc;
      padding:.3rem .85rem;
      border-radius:999px;
      margin-bottom:1.5rem;
    }}

    h1{{
      font-size:2.4rem;
      font-weight:700;
      background:linear-gradient(90deg,#818cf8,#c084fc);
      -webkit-background-clip:text;
      -webkit-text-fill-color:transparent;
      margin-bottom:.5rem;
    }}

    .subtitle{{
      font-size:1rem;
      color:#94a3b8;
      margin-bottom:2.5rem;
    }}

    .meta{{
      display:flex;
      flex-direction:column;
      gap:.75rem;
    }}

    .meta-row{{
      display:flex;
      justify-content:space-between;
      align-items:center;
      background:rgba(255,255,255,.04);
      padding:.65rem 1rem;
      border-radius:.6rem;
      font-size:.875rem;
    }}

    .meta-label{{
      color:#64748b;
      font-weight:500;
    }}

    .meta-value{{
      color:#cbd5e1;
      font-family:"SF Mono",SFMono-Regular,Menlo,Consolas,monospace;
      font-size:.82rem;
    }}

    .footer{{
      margin-top:2rem;
      font-size:.7rem;
      color:#475569;
    }}
  </style>
</head>
<body>
  <main class="card">
    <span class="badge">AKS PoC Service</span>
    <h1>Hello, World!</h1>
    <p class="subtitle">FastAPI + Uvicorn on Kubernetes</p>
    <div class="meta">
      <div class="meta-row">
        <span class="meta-label">Server Time</span>
        <span class="meta-value">{server_time}</span>
      </div>
      <div class="meta-row">
        <span class="meta-label">Port</span>
        <span class="meta-value">{port}</span>
      </div>
      <div class="meta-row">
        <span class="meta-label">Runtime</span>
        <span class="meta-value">Python 3.12</span>
      </div>
    </div>
    <p class="footer">Running as non-root &middot; Ready for production</p>
  </main>
</body>
</html>"""
