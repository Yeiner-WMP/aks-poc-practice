# Step-by-Step Guide: Deploying a Kubernetes Cluster to Azure with Terraform

    - A hands-on, walkthrough.
    - Follow every step in order. 
    - Do not skip ahead.
    - By the end, you will have built and deployed a working Kubernetes application to Azure entirely through code and automation.

---

## Before You Start

### What You Will Build

You will deploy a Python FastAPI web application to Azure Kubernetes Service (AKS), automated end-to-end with Terraform and GitHub Actions. When you are done, anyone in the world can visit a public URL and see a styled "Hello, World!" page showing the server time and port.

### What You Will Learn

By completing this guide, you will understand:

- How to write and containerize a Python application (Docker + FastAPI + Uvicorn)
- How to define cloud infrastructure as code (Terraform)
- How to automate deployments with CI/CD pipelines (GitHub Actions)
- How to manage a Kubernetes cluster (AKS)
- How to securely connect services using managed identities (Azure OIDC)
- How to troubleshoot deployments at every layer

### Time Estimate

- First read-through: ~1 hour
- Full hands-on execution: ~5-6 hours (most of it is waiting for Azure resources to provision)

### Skill Prerequisites

- Basic command-line comfort (you can run commands in a terminal)
- Basic Git knowledge (clone, commit, push)
- A willingness to read error messages carefully

You do **not** need prior experience with Azure, Terraform, Kubernetes, or Docker.

---

## Phase 0: Understand the Repository

**Goal:** Understand what you are building before you touch anything.

### Step 0.1: Read the Documentation

Read these files in the repository, in this order:

1. **`README.md`** -- High-level overview: what the project does, how it is structured, how to deploy
2. **`terraform/acr/README.md`** -- What the ACR module creates, its inputs and state management
3. **`terraform/aks/README.md`** -- What the AKS module creates, container image reference, Kubernetes naming conventions

Do not skim. Read every section. If a term is unfamiliar, look it up before continuing.

### Step 0.2: Understand the Architecture

Memorize this flow -- it is the backbone of everything you will build:

```
app/main.py --> Dockerfile --> Container Image --> ACR --> AKS --> Public URL
                                                    ^
                                                    |
                                         Terraform defines all of this
                                                    ^
                                                    |
                                         GitHub Actions automates it
```

There are two separate deployments:

| Deployment | What It Creates | Terraform Path | Workflow File |
|---|---|---|---|
| **ACR** | Azure Container Registry (image storage) | `terraform/acr/` | `.github/workflows/deploy_acr.yaml` |
| **AKS** | Kubernetes cluster + app deployment | `terraform/aks/` | `.github/workflows/deploy_aks.yaml` |

**Why separate?** ACR is created once and rarely changes. AKS changes with every app deployment. Separating them means you can redeploy the app without risking the image registry.

### Step 0.3: Trace the Code

Open each file and understand what it does. Trace the connections:

```
terraform/aks/variables.tf  defines  var.acr_name
    --> used in terraform/aks/main.tf  to look up ACR via data source
    --> used in the Deployment image path: ${var.acr_name}.azurecr.io/${var.image_name}:${var.image_tag}
    --> value comes from GitHub Actions variable ACR_NAME
    --> exported as TF_VAR_acr_name in deploy_aks.yaml
```

Do this for at least 3 variables. This exercise builds your mental model of how configuration flows through the system.

### Step 0.4: Understand the Application

The application lives in `app/main.py`. Key things to note:

| Aspect | Detail |
|---|---|
| **Framework** | FastAPI (async Python web framework) |
| **Server** | Uvicorn (ASGI server) |
| **Port** | Reads from `PORT` env var, defaults to `8080` |
| **`GET /`** | Returns a styled HTML page with greeting, server time (UTC), and port |
| **`GET /healthz`** | Returns `{"status":"ok"}` -- used by Kubernetes probes |
| **Logging** | Middleware logs every request; startup message logs the port |
| **Container user** | Runs as non-root `app` user (required by AKS security standards) |

### Step 0.5: Understand the Project Structure

```
aks-poc-practice/
├── app/
│   ├── __init__.py                      # Makes app/ a Python package
│   └── main.py                          # FastAPI application (routes, middleware, HTML template)
├── terraform/
│   ├── acr/
│   │   ├── main.tf                      # ACR resource definition
│   │   ├── providers.tf                 # AzureRM provider + backend config
│   │   ├── variables.tf                 # Input variables
│   │   ├── vars/
│   │   │   └── poc.tfvars               # Environment-specific values
│   │   └── README.md
│   └── aks/
│       ├── main.tf                      # AKS cluster + K8s resources + ACR role assignment
│       ├── providers.tf                 # AzureRM + Kubernetes providers + backend config
│       ├── variables.tf                 # Input variables
│       ├── vars/
│       │   └── poc.tfvars               # Environment-specific values
│       └── README.md
├── .github/
│   └── workflows/
│       ├── deploy_acr.yaml              # ACR plan/apply/destroy workflow
│       └── deploy_aks.yaml              # AKS plan/apply/destroy workflow (includes Docker build+push)
├── Dockerfile                           # python:3.12-slim, non-root, layer-cached
├── requirements.txt                     # FastAPI + Uvicorn
├── .dockerignore
├── .gitignore
└── README.md
```

---

## Phase 1: Set Up Azure Prerequisites

**Goal:** Create the Azure resources that Terraform expects to already exist.

> Terraform in this project does NOT create the Resource Group or the state storage.
> You must create these manually (or with a separate script) before running any workflows.

### Step 1.1: Log In to Azure

Install the Azure CLI if you have not already, then authenticate:

```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Log in
az login
```

Verify you are in the correct subscription:

```bash
az account show --query "{name:name, id:id}" -o table
```

If you need to switch subscriptions:

```bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

### Step 1.2: Create a Resource Group

This is the container for all your Azure resources.

```bash
az group create \
  --name "yaguirre-aks-poc" \
  --location "eastus"
```

**Why "eastus"?** It is a common, well-supported region. You can use any region, but be consistent -- all resources should be in the same region.

Verify it exists:

```bash
az group show --name "yaguirre-aks-poc" --query "{name:name, location:location}" -o table
```

### Step 1.3: Create a Storage Account for Terraform State

Terraform needs remote storage to keep track of what it has created. This is critical for team collaboration and CI/CD.

```bash
# Storage account names must be globally unique, lowercase, no hyphens, 3-24 chars
# Replace <UNIQUE_NAME> with something like "akspocpracticetfstate"
az storage account create \
  --name "<UNIQUE_NAME>" \
  --resource-group "yaguirre-aks-poc" \
  --location "eastus" \
  --sku "Standard_LRS" \
  --min-tls-version "TLS1_2" \
  --tags \
    "Owner 1=yaguirre@westmonroe.com" \
    "Owner 2=agreenwald@westmonroe.com" \
    "Client Code=Jepp-POC"
```

Create a blob container inside the storage account:

```bash
az storage container create \
  --name "tfstate" \
  --account-name "<UNIQUE_NAME>"
```

**Write down these three values. You will need them later as GitHub Secrets:**

| Value | Example |
|---|---|
| Resource Group Name | `yaguirre-aks-poc` |
| Storage Account Name | `akspocpracticetfstate` |
| Container Name | `tfstate` |

### Step 1.4: Create a User-Assigned Managed Identity for GitHub OIDC

This allows GitHub Actions to authenticate to Azure without secrets (OIDC).

#### Step 1.4.1: Create the User-Assigned Managed Identity

```bash
az identity create \
  --name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --location "eastus"
```

Capture the Client ID and Principal ID:

```bash
MI_CLIENT_ID=$(az identity show \
  --name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --query clientId -o tsv)

MI_PRINCIPAL_ID=$(az identity show \
  --name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --query principalId -o tsv)

echo "MI_CLIENT_ID=$MI_CLIENT_ID"
echo "MI_PRINCIPAL_ID=$MI_PRINCIPAL_ID"
```

#### Step 1.4.2: Assign Azure RBAC Roles to the Managed Identity

Assign **Contributor** on your resource group (allows creating resources):

```bash
az role assignment create \
  --assignee-object-id "$MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/yaguirre-aks-poc"
```

Assign **User Access Administrator** on the resource group (allows creating role assignments, needed for the AcrPull grant):

```bash
az role assignment create \
  --assignee-object-id "$MI_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/yaguirre-aks-poc"
```

> **Why User Access Administrator?** The AKS Terraform module creates an `azurerm_role_assignment` to grant the cluster's kubelet identity `AcrPull` on the ACR. This requires `Microsoft.Authorization/roleAssignments/write`, which `Contributor` alone does not provide.

#### Step 1.4.3: Configure Federated Credentials (GitHub OIDC Trust)

You need two credentials: one for the `main` branch and one for the `poc` environment.

**A) Credential for main branch:**

```bash
az identity federated-credential create \
  --name "github-aks-poc-main" \
  --identity-name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"
```

**B) Credential for GitHub Environment `poc`:**

```bash
az identity federated-credential create \
  --name "github-aks-poc-env" \
  --identity-name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:environment:poc" \
  --audiences "api://AzureADTokenExchange"
```

#### Step 1.4.4: GitHub Secrets to Create

You will set these GitHub secrets in Phase 2:

| Secret Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `MI_CLIENT_ID` (managed identity clientId) |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |

### Step 1.5: Verify All Prerequisites

Run these commands and confirm each returns a valid result:

```bash
# Resource Group exists
az group show --name "yaguirre-aks-poc" -o table

# Storage Account exists
az storage account show --name "<STORAGE_ACCOUNT_NAME>" -o table

# Blob container exists
az storage container show --name "tfstate" --account-name "<STORAGE_ACCOUNT_NAME>" -o table

# Managed identity exists
az identity show \
  --name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --query "{name:name, clientId:clientId, principalId:principalId}" \
  -o table

# Federated credentials exist (main + environment:poc)
az identity federated-credential list \
  --identity-name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc" \
  --query "[].{name:name, issuer:issuer, subject:subject, audiences:audiences}" \
  -o table

# Role assignments exist
az role assignment list \
  --assignee "$MI_PRINCIPAL_ID" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/yaguirre-aks-poc" \
  --query "[].{role:roleDefinitionName, scope:scope}" \
  -o table
```

**Checkpoint:** If all six commands succeed, you are ready to proceed.

---

## Phase 2: Set Up the GitHub Repository

**Goal:** Configure your GitHub repo with the code, variables, and secrets needed for automation.

### Step 2.1: Fork or Copy the Repository

**Option A: Fork** (recommended for learning)

1. Go to the repository on GitHub
2. Click "Fork"
3. This creates your own copy you can modify freely

**Option B: New repository**

1. Create a new repository on GitHub
2. Clone it locally
3. Copy all files from the repo into your new repo
4. Push

### Step 2.2: Configure GitHub Repository Variables

Go to your repo on GitHub: **Settings > Secrets and variables > Actions > Variables tab**

Create these **repository variables**:

| Variable Name | Value | Notes |
|---|---|---|
| `ACR_NAME` | A globally unique name (e.g., `acrakspocpractice`) | Must be alphanumeric only, 5-50 chars, globally unique across ALL of Azure |
| `IMAGE_NAME` | `helloworld-python-poc` | The name of your Docker image inside ACR |

**Why are these variables, not secrets?** They are not sensitive -- anyone can see your ACR name. Secrets are for values that must stay hidden (like authentication credentials).

### Step 2.3: Configure GitHub Repository Secrets

Go to: **Settings > Secrets and variables > Actions > Secrets tab**

Create these **repository secrets**:

| Secret Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | The managed identity Client ID from Step 1.4 |
| `AZURE_TENANT_ID` | Your Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Your Azure Subscription ID |
| `BACKEND_AZURE_RESOURCE_GROUP_NAME` | `yaguirre-aks-poc` |
| `BACKEND_AZURE_STORAGE_ACCOUNT_NAME` | Your storage account name from Step 1.3 |
| `BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME` | `tfstate` |

**Double-check every value.** A single typo here will cause cryptic errors in your workflows.

### Step 2.4: Create a GitHub Environment

Go to: **Settings > Environments > New environment**

1. Name it: `poc`
2. Optionally add yourself as a **Required reviewer** -- this creates a manual approval gate before apply jobs run

**Why?** The apply job in each workflow references `environment: poc`. With a required reviewer, you get to inspect the Terraform plan before anything is created or destroyed.

### Step 2.5: Verify GitHub Configuration

Checklist:

- [ ] Repository has all code files (check that `.github/workflows/` exists with both `.yaml` files)
- [ ] 2 repository variables are set (`ACR_NAME`, `IMAGE_NAME`)
- [ ] 6 repository secrets are set (the `AZURE_*` and `BACKEND_AZURE_*` ones)
- [ ] GitHub Actions is enabled (Settings > Actions > General)
- [ ] `poc` environment is created

---

## Phase 3: Deploy ACR (Azure Container Registry)

**Goal:** Create the container registry that will store your Docker images.

### Step 3.1: Trigger the ACR Workflow

1. Go to your repo on GitHub
2. Click the **Actions** tab
3. In the left sidebar, click **Deploy ACR Terraform**
4. Click **Run workflow**
5. Set:
   - **action:** `plan -> apply`
   - **environment:** `poc`
6. Click **Run workflow**

### Step 3.2: Review the Plan

1. Click on the running workflow to watch it
2. The **Plan** job will run first
3. Expand the "Terraform Plan" step
4. Read the output -- it should show something like:

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

This means Terraform wants to create 1 resource (the ACR). This is expected.

**If the plan shows errors:**
- `Error: building account: could not acquire access token` -- Check your OIDC secrets
- `Error: storage: service returned error` -- Check your backend storage secrets
- `Error: No value for required variable` -- Check that `ACR_NAME` is set as a GitHub variable (not secret)

### Step 3.3: Approve the Apply (if you set up environment protection)

If you configured required reviewers on the `poc` environment:
1. You will see a "Review deployments" prompt
2. Click it and approve

### Step 3.4: Verify ACR Was Created

After the Apply job succeeds:

```bash
az acr show --name "<ACR_NAME>" --query "{name:name, loginServer:loginServer, sku:sku.name}" -o table
```

Expected output:

```
Name               LoginServer                   Sku
-----------------  ----------------------------  -----
acrakspocpractice  acrakspocpractice.azurecr.io  Basic
```

**Checkpoint:** ACR exists and is accessible. Proceed to Phase 4.

---

## Phase 4: Deploy AKS and the Application

**Goal:** Create the Kubernetes cluster, build the Docker image, push it to ACR, and deploy the app.

### Step 4.1: Trigger the AKS Workflow

1. Go to the **Actions** tab
2. Click **Deploy AKS Terraform**
3. Click **Run workflow**
4. Set:
   - **action:** `plan -> apply`
   - **environment:** `poc`
5. Click **Run workflow**

### Step 4.2: Review the Plan

The Plan job output should show something like:

```
Plan: 5 to add, 0 to change, 0 to destroy.
```

**Azure Resources:**

1. `azurerm_kubernetes_cluster.aks` -- AKS cluster named `aks-poc-cluster` in East US
2. `azurerm_role_assignment.this` -- Grants `AcrPull` to the cluster's kubelet identity on the ACR

**Kubernetes Resources:**

3. `kubernetes_namespace_v1.hello_world_ns` -- Namespace `hello-world`
4. `kubernetes_deployment_v1.hello_world_app` -- Deployment running the FastAPI container from ACR
5. `kubernetes_service_v1.hello_world_service` -- LoadBalancer service exposing the app on port 80

> Read the plan carefully. Understand every resource being created.

### Step 4.3: Approve and Wait

1. Approve the deployment (if environment protection is enabled)
2. The Apply job will:
   - Build the Docker image (python:3.12-slim + FastAPI + Uvicorn)
   - Push it to ACR tagged with the Git commit SHA
   - Create the AKS cluster (this takes 5-10 minutes)
   - Deploy Kubernetes resources (namespace, deployment, service)
3. Wait for the workflow to complete successfully

**Common errors at this stage:**

| Error | Cause | Fix |
|---|---|---|
| `denied: requested access to the resource is denied` | ACR login failed | Check that `ACR_NAME` variable matches what you created |
| `QuotaExceeded` | Your subscription hit a VM quota | Request a quota increase in Azure Portal or use a smaller VM size |
| `AuthorizationFailed: ...roleAssignments/write` | Missing RBAC permission | Assign `User Access Administrator` to the managed identity (Step 1.4.2) |

### Step 4.4: Find the Public IP

After the workflow succeeds, find the LoadBalancer external IP:

**Option A: Azure CLI**

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group "yaguirre-aks-poc" \
  --name "aks-poc-cluster"

# Find the external IP
kubectl get svc -n hello-world
```

Look for the `EXTERNAL-IP` column on the `hello-world-service` row.

**Option B: Azure Portal**

1. Go to the Azure Portal
2. Navigate to your Resource Group
3. Click on the AKS cluster
4. Go to **Services and ingresses**
5. Find the external IP

### Step 4.5: Test the Application

```bash
# Test the landing page
curl -s http://<EXTERNAL-IP>/

# Test the health endpoint
curl -s http://<EXTERNAL-IP>/healthz
```

Expected responses:

- `/` -- An HTML page containing "Hello, World!", the server time, and port 8080
- `/healthz` -- `{"status":"ok"}`

You can also open `http://<EXTERNAL-IP>/` in a browser to see the styled landing page with the dark gradient card design.

**Checkpoint:** If you see the HTML page and health check, your entire deployment pipeline works end to end. Congratulations.

---

## Phase 5: Understand What You Built (Post-Deployment Exploration)

**Goal:** Go beyond "it works" and truly understand every layer.

> A master craftsman does not just follow instructions. They understand the *why* behind every decision.

### Step 5.1: Explore the Kubernetes Cluster

Get your cluster credentials (if you have not already):

```bash
az aks get-credentials \
  --resource-group "yaguirre-aks-poc" \
  --name "aks-poc-cluster"
```

Now explore:

```bash
# List all namespaces -- find yours
kubectl get namespaces

# List all resources in your namespace
kubectl get all -n hello-world

# Describe the deployment -- see the full configuration
kubectl describe deployment hello-world-app -n hello-world

# Describe the service -- see the LoadBalancer details
kubectl describe svc hello-world-service -n hello-world

# View pod logs -- see the startup message and request logs
kubectl logs -n hello-world -l app=hello-world

# Check pod health
kubectl get pods -n hello-world -o wide
```

**Questions to answer yourself:**
- What image tag is the pod running? (Check with `kubectl describe pod`)
- What is the pod's IP address? Is it the same as the external IP?
- What node is the pod running on?
- Can you see the `Listening on http://0.0.0.0:8080/` startup log?

### Step 5.2: Explore the Terraform State

```bash
# From the terraform/aks directory (after terraform init)
cd terraform/aks

# List all resources Terraform is tracking
terraform state list

# Show details of a specific resource
terraform state show azurerm_kubernetes_cluster.aks

# Show all outputs
terraform output
```

**Questions to answer yourself:**
- How many resources is Terraform managing?
- What happens if you delete a resource from Azure Portal -- does Terraform know?
- What information does the state store about the AKS cluster?

### Step 5.3: Explore the Container Image

```bash
# List images in your ACR
az acr repository list --name "<ACR_NAME>" -o table

# List tags for your image
az acr repository show-tags --name "<ACR_NAME>" --repository "helloworld-python-poc" -o table

# Show image details
az acr repository show --name "<ACR_NAME>" --image "helloworld-python-poc:<TAG>" -o jsonc
```

**Questions to answer yourself:**
- What is the image tag? Does it match a Git commit SHA?
- How large is the image?
- If you push a new commit, will a new tag appear?

### Step 5.4: Trace a Request End to End

Follow a single HTTP request through every layer:

```
1. You run: curl http://<EXTERNAL-IP>/
2. DNS resolves the IP to an Azure Load Balancer
3. The Load Balancer forwards port 80 to a node in the AKS cluster
4. The node's kube-proxy routes to the hello-world-service
5. The service selects a pod with label app=hello-world
6. The pod's container receives the request on port 8080
7. FastAPI's root handler builds the HTML page with current UTC time
8. Uvicorn sends the response back through every layer to your terminal
```

Verify this by checking:

```bash
# The service endpoints (internal pod IPs)
kubectl get endpoints hello-world-service -n hello-world

# The pod IP (should match the endpoint)
kubectl get pods -n hello-world -o wide
```

---

## Phase 6: Break Things and Fix Them

**Goal:** Build confidence by deliberately causing failures and resolving them.

> You do not truly understand a system until you have broken it and repaired it.

### Step 6.1: Kill a Pod

```bash
# Delete a pod
kubectl delete pod -n hello-world -l app=hello-world

# Immediately watch what happens
kubectl get pods -n hello-world -w
```

**What you should see:** Kubernetes automatically creates a new pod to replace the one you deleted. This is because the Deployment's `replicas: 1` specification declares intent -- Kubernetes continuously reconciles actual state with desired state.

### Step 6.2: Check Health Probes

```bash
# Describe the pod and look for probe status
kubectl describe pod -n hello-world -l app=hello-world | grep -A 5 "Liveness\|Readiness"
```

**What to look for:** The `Liveness` and `Readiness` probes should both show `http-get http://:8080/`. The readiness probe targets `/` (the HTML page) and the liveness probe also targets `/`. Both return 200 when the app is healthy.

> **Note:** For a production service, you would typically point probes at `/healthz` instead of `/`. The current setup works because the root path is lightweight and always returns 200.

### Step 6.3: Check Workflow Logs

Go back to the GitHub Actions runs:

1. Click on a completed run
2. Expand each step
3. Read the logs for:
   - Terraform plan output (what was created)
   - Docker build output (how the image was built)
   - Terraform apply output (confirmation of changes)

**Master craftsman habit:** Always read your pipeline logs, even when things succeed. You will often catch warnings or inefficiencies that help you improve.

---

## Phase 7: Clean Up (Destroy)

**Goal:** Tear down everything to avoid ongoing Azure costs.

> Always destroy resources when you are done learning. Cloud costs accumulate even when resources are idle.

### Step 7.1: Destroy AKS First

1. Go to **Actions** > **Deploy AKS Terraform**
2. **Run workflow** with:
   - **action:** `destroy`
   - **environment:** `poc`
3. Wait for completion

The AKS destroy uses `-target` flags to destroy resources in the correct dependency order (K8s resources first, then the cluster itself).

### Step 7.2: Destroy ACR Second

1. Go to **Actions** > **Deploy ACR Terraform**
2. **Run workflow** with:
   - **action:** `destroy`
   - **environment:** `poc`
3. Wait for completion

### Step 7.3: Verify Everything Is Gone

```bash
# Should return "not found"
az aks show --resource-group "yaguirre-aks-poc" --name "aks-poc-cluster" 2>&1

# Should return "not found"
az acr show --name "<ACR_NAME>" 2>&1
```

### Step 7.4: (Optional) Clean Up Azure Prerequisites

If you are completely done and will not redeploy:

```bash
# Delete the entire resource group (removes storage account too)
az group delete --name "yaguirre-aks-poc" --yes

# Delete the managed identity (already deleted with the resource group above,
# but if it was in a different RG you would run:)
az identity delete \
  --name "github-actions-aks-poc-mi" \
  --resource-group "yaguirre-aks-poc"
```

---

## Phase 8: Level Up -- Iteration Challenges

**Goal:** Go from "I followed the guide" to "I understand the system deeply."

These challenges are ordered by difficulty. Complete them one at a time, in order. Each builds on the previous.

### Challenge 1: Point Probes at `/healthz`

**Difficulty:** Beginner

Update the Kubernetes Deployment in `terraform/aks/main.tf` to point both `readiness_probe` and `liveness_probe` at `/healthz` instead of `/`. This is the proper pattern -- health probes should hit a lightweight JSON endpoint, not the full HTML page.

**Verification:** Deploy, then run `kubectl describe pod` and confirm probes target `/healthz`.

### Challenge 2: Add Terraform Outputs

**Difficulty:** Beginner

Add `outputs.tf` files to both `terraform/acr/` and `terraform/aks/` that surface useful information:

- ACR: registry name, login server URL
- AKS: cluster name, service external IP, namespace name

**Why this matters:** Outputs make Terraform configurations self-documenting and enable automation to consume values programmatically.

**Verification:** Run `terraform output` and see your values. Add them to the GitHub Actions job summary using `$GITHUB_STEP_SUMMARY`.

### Challenge 3: Add a Formatting Check to CI

**Difficulty:** Beginner

Add a new GitHub Actions workflow that:
- Triggers on pull requests
- Runs `terraform fmt -check -recursive`
- Fails if any file is not properly formatted

**Why this matters:** Consistent formatting prevents meaningless diffs in code review and enforces team standards.

### Challenge 4: Make the App Port Configurable

**Difficulty:** Intermediate

Add Terraform variables for the container port and service port. Pass the port to the container via the `PORT` environment variable in the Kubernetes Deployment spec.

**Verification:** Deploy with port 9090 instead of 8080 and confirm the app still works (the FastAPI app already reads `PORT` from the environment).

**Why this matters:** Hardcoded values are the enemy of reusability. Learning to thread configuration through multiple layers (Terraform variable > K8s env var > Python app) is a fundamental skill.

### Challenge 5: Add Resource Requests and Limits

**Difficulty:** Intermediate

Add CPU and memory requests and limits to the Kubernetes Deployment:

```hcl
resources {
  requests = { cpu = "100m", memory = "128Mi" }
  limits   = { cpu = "250m", memory = "256Mi" }
}
```

**Why this matters:** Without resource limits, a single misbehaving container can consume all node resources and crash other workloads. This is a production-critical practice.

### Challenge 6: Add a Second Environment

**Difficulty:** Advanced

Create a `dev.tfvars` file alongside `poc.tfvars`. Add `dev` as an option in the workflow `environment` input. Deploy both environments and confirm they are fully independent.

**Why this matters:** Real projects always have multiple environments (dev, staging, prod). Learning to parameterize your infrastructure for multiple environments is essential.

---

## Quick Reference Card

### Key Commands

```bash
# Azure CLI
az login
az account show
az group show --name "yaguirre-aks-poc"
az acr show --name "<ACR_NAME>"
az aks get-credentials --resource-group "yaguirre-aks-poc" --name "aks-poc-cluster"

# Kubernetes
kubectl get namespaces
kubectl get all -n hello-world
kubectl get pods -n hello-world -o wide
kubectl logs -n hello-world -l app=hello-world
kubectl describe pod -n hello-world -l app=hello-world

# Terraform (from terraform/acr or terraform/aks directory)
terraform init
terraform validate
terraform plan -var-file="vars/poc.tfvars"
terraform apply -var-file="vars/poc.tfvars"
terraform destroy -var-file="vars/poc.tfvars"
terraform state list
terraform output
```

### Key Files

| File | What It Does |
|---|---|
| `app/main.py` | FastAPI application (routes, middleware, HTML template) |
| `Dockerfile` | Packages the app into a container image (python:3.12-slim, non-root) |
| `requirements.txt` | Python dependencies (FastAPI + Uvicorn) |
| `terraform/acr/main.tf` | Creates Azure Container Registry |
| `terraform/aks/main.tf` | Creates AKS cluster + K8s resources + ACR role assignment |
| `.github/workflows/deploy_acr.yaml` | Automates ACR deployment (plan/apply/destroy) |
| `.github/workflows/deploy_aks.yaml` | Automates AKS + app deployment (plan/build/push/apply/destroy) |

### Troubleshooting Cheat Sheet

| Symptom | Check | Fix |
|---|---|---|
| Workflow fails at Azure login | OIDC secrets in GitHub | Verify `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |
| Workflow fails at terraform init | Backend secrets in GitHub | Verify `BACKEND_AZURE_*` secrets match your storage account |
| Terraform plan shows errors | Variable values | Check `ACR_NAME` and `IMAGE_NAME` GitHub variables |
| `AuthorizationFailed: ...roleAssignments/write` | RBAC permissions | Assign `User Access Administrator` to the managed identity |
| Docker push fails | ACR permissions | Verify managed identity has Contributor role on resource group |
| Pod stuck in `ImagePullBackOff` | AcrPull role assignment | Run `kubectl describe pod` and check Events section |
| Pod stuck in `CrashLoopBackOff` | Application error | Run `kubectl logs` to see Python/Uvicorn output |
| Service has no External IP | LoadBalancer provisioning | Wait 2-3 minutes; check `kubectl get svc -n hello-world -w` |
| `curl` returns connection refused | Wrong IP or port | Verify the external IP and that you are using port 80, not 8080 |
| Destroy fails with "No value for required variable" | Missing `-var-file` | Ensure destroy step includes `-var-file="vars/<env>.tfvars"` |

---

## The Craftsman's Mindset

1. **Read before you run.** Understand every command before executing it.
2. **Read the error message.** The answer is almost always in the error output.
3. **Check the logs.** Workflow logs, Terraform output, pod logs -- always read them.
4. **Understand the layers.** Code > Container > Registry > Cluster > Service > User. Know which layer your problem is in.
5. **Break things on purpose.** Delete a pod. Change a variable. See what happens. Repair it.
6. **Destroy and recreate.** The whole point of IaC is that infrastructure is disposable and reproducible. Prove it.
7. **Document what you learn.** When you solve a problem, write it down. Your future self will thank you.
8. **Ask why, not just how.** "How do I create an ACR?" is a beginner question. "Why is ACR separate from AKS in the Terraform code?" is a craftsman's question.
