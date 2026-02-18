# AKS PoC — Python Web Service

Production-ready FastAPI web service deployed to Azure Kubernetes Service (AKS) with Terraform and GitHub Actions. Fully automated infrastructure-as-code pipeline: push code, build container, deploy to Kubernetes.

## Architecture

```
app/main.py ──> Dockerfile ──> Container Image ──> ACR ──> AKS ──> Public URL
                                                    │
                                          Terraform defines all of this
                                                    │
                                          GitHub Actions automates it
```

| Layer | Technology |
|-------|-----------|
| Application | Python 3.12 · FastAPI · Uvicorn |
| Container | Docker · python:3.12-slim · non-root |
| Registry | Azure Container Registry (ACR) |
| Orchestration | Azure Kubernetes Service (AKS) |
| Infrastructure | Terraform (AzureRM + Kubernetes providers) |
| CI/CD | GitHub Actions · OIDC authentication |

## Project Structure

```
aks-poc-practice/
├── app/
│   ├── __init__.py
│   └── main.py                          # FastAPI app (routes, middleware, HTML template)
├── terraform/
│   ├── acr/                             # ACR module (container registry)
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   └── vars/poc.tfvars
│   └── aks/                             # AKS module (cluster + K8s resources)
│       ├── main.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── vars/poc.tfvars
├── .github/workflows/
│   ├── deploy_acr.yaml                  # ACR plan / apply / destroy
│   └── deploy_aks.yaml                  # AKS plan / build+push / apply / destroy
├── Dockerfile
├── requirements.txt
├── Step-by-Step Guide.md                # Full walkthrough for first-time deployment
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

### Full AKS deployment

See **[Step-by-Step Guide.md](Step-by-Step%20Guide.md)** for the complete walkthrough — from Azure prerequisites through GitHub Actions to a live public URL.

## Endpoints

| Method | Path       | Content-Type               | Description                          |
|--------|------------|----------------------------|--------------------------------------|
| GET    | `/`        | `text/html; charset=utf-8` | Styled landing page (greeting, server time, port) |
| GET    | `/healthz` | `application/json`         | `{"status":"ok"}` — Kubernetes probe target |

## Configuration

| Variable | Default | Description        |
|----------|---------|--------------------|
| `PORT`   | `8080`  | Server listen port |

## Deployment Workflows

Both workflows are triggered manually via **Actions > Run workflow** with `plan -> apply` or `destroy`.

### Deploy ACR (`deploy_acr.yaml`)

Creates the Azure Container Registry. Run this **once** before deploying AKS.

- **Plan** — `terraform plan` with environment tfvars
- **Apply** — requires environment approval, then `terraform apply`
- **Destroy** — `terraform destroy` with environment tfvars

### Deploy AKS (`deploy_aks.yaml`)

Creates the AKS cluster, builds and pushes the Docker image, and deploys Kubernetes resources.

- **Plan** — `terraform plan` (image tagged with Git SHA)
- **Apply** — builds Docker image, pushes to ACR, applies the Terraform plan
- **Destroy** — targeted destroy of K8s resources + AKS cluster

### GitHub Configuration Required

**Repository Variables:**

| Name | Example | Purpose |
|------|---------|---------|
| `ACR_NAME` | `acrakspocpractice` | ACR registry name |
| `IMAGE_NAME` | `helloworld-python-poc` | Docker image repository name |

**Repository Secrets:**

| Name | Purpose |
|------|---------|
| `AZURE_CLIENT_ID` | Managed identity Client ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |
| `BACKEND_AZURE_RESOURCE_GROUP_NAME` | Terraform state storage RG |
| `BACKEND_AZURE_STORAGE_ACCOUNT_NAME` | Terraform state storage account |
| `BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME` | Terraform state blob container |

**Environment:** `poc` (with optional required reviewer for approval gates)

## Application Design

| Decision | Rationale |
|----------|-----------|
| **FastAPI + Uvicorn** | Async-ready, high performance, minimal boilerplate |
| **Inline HTML/CSS** | Zero external dependencies — renders offline, single-request load |
| **`_render_page()` as pure function** | Separates template logic from route handling; trivially testable |
| **HTTP middleware for logging** | Captures every request method + path + status without touching route code |
| **No Swagger UI** | `docs_url=None` reduces attack surface in production |

## Container Security

| Practice | Detail |
|----------|--------|
| Minimal base image | `python:3.12-slim` |
| Non-root user | System user `app` — no login shell, no home directory |
| No bytecode | `PYTHONDONTWRITEBYTECODE=1` |
| Unbuffered output | `PYTHONUNBUFFERED=1` for reliable container log collection |
| Layer caching | Dependencies installed before app code — faster rebuilds |
| K8s compatible | Works with `runAsNonRoot: true` and restricted Pod Security Standards |

## Infrastructure Design

| Decision | Rationale |
|----------|-----------|
| **ACR and AKS in separate Terraform modules** | ACR is stable; AKS changes with every deploy. Separation reduces blast radius |
| **No Terraform remote state references** | AKS looks up ACR by name via `data` source — keeps modules loosely coupled |
| **OIDC authentication** | No stored secrets for Azure auth — GitHub Actions exchanges a token directly |
| **System-assigned AKS identity** | Simplest auth model; Terraform grants `AcrPull` via role assignment |
| **Targeted destroy for AKS** | Destroys K8s resources before the cluster to avoid orphaned state |
| **`-var-file` on all paths** | Plan, apply, and destroy all receive the same tfvars to prevent missing-variable errors |
