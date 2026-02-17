# Azure Kubernetes Service (AKS) Terraform

This Terraform configuration deploys an **Azure Kubernetes Service (AKS)** cluster and the **Kubernetes resources** needed to run the Hello World container image.

- The Azure Resource Group is **not created** here; it is looked up via a Terraform data source (`data.azurerm_resource_group`).
- The ACR is **not referenced via Terraform remote state**. Instead, this module looks up the registry by name using `data.azurerm_container_registry`.

## Resources

### Azure (azurerm provider)

- `azurerm_kubernetes_cluster` — creates the AKS cluster.
- `azurerm_role_assignment` — grants the cluster’s kubelet identity the `AcrPull` role on the ACR.
- `data.azurerm_container_registry` — reads the existing ACR by name (used as the role assignment scope).

### Kubernetes (kubernetes provider)

- `kubernetes_namespace_v1` — namespace for the app.
- `kubernetes_deployment_v1` — runs the container image.
- `kubernetes_service_v1` — exposes the deployment via a `LoadBalancer` service.

## Container image reference

The image used by the Kubernetes Deployment is constructed as:

- `${acr_name}.azurecr.io/${image_name}:${image_tag}`

Where:

- `acr_name` is provided via workflow environment (`TF_VAR_acr_name`).
- `image_name` is provided via workflow environment (`TF_VAR_image_name`).
- `image_tag` is passed at runtime (typically the Git SHA).

## Kubernetes naming convention

Kubernetes names and labels are derived from `app_name`:

- Namespace: `app_name`
- App label: `app_name`
- Deployment name: `${app_name}-app`
- Service name: `${app_name}-service`

## Inputs

| Name | Type | Required | Default | Source | Description |
|------|------|----------|---------|--------|-------------|
| `resource_group_name` | `string` | Yes | n/a | `vars/<env>.tfvars` | Name of the existing Azure Resource Group where AKS is deployed. |
| `aks_name` | `string` | Yes | n/a | `vars/<env>.tfvars` | Name of the AKS cluster. |
| `aks_dns_prefix` | `string` | Yes | n/a | `vars/<env>.tfvars` | DNS prefix for the AKS cluster. |
| `app_name` | `string` | Yes | n/a | `vars/<env>.tfvars` | Application name used to derive Kubernetes namespace/labels/resource names. |
| `tags` | `map(string)` | Yes | n/a | `vars/<env>.tfvars` | Tags applied to Azure resources. Tag keys (e.g., `"Owner 1"`, `"Owner 2"`, `"Client Code"`) are expected to remain the same. |
| `acr_name` | `string` | Yes | n/a | Workflow env (`TF_VAR_acr_name`) | Name of the Azure Container Registry used for image pull permissions and image URL construction. |
| `image_name` | `string` | Yes | n/a | Workflow env (`TF_VAR_image_name`) | Image repository name within ACR. |
| `image_tag` | `string` | Yes | n/a | Workflow runtime var | Image tag (typically the Git SHA). |
| `default_node_pool_node_count` | `number` | No | `1` | Terraform default | Node count for the default node pool. |
| `default_node_pool_vm_size` | `string` | No | `Standard_DS2_v2` | Terraform default | VM size for the default node pool. |

## State

This module uses an **AzureRM remote backend**. Backend configuration is supplied at runtime by the GitHub Actions workflow.

State key convention used by the workflow:

- `aks_<environment>.tfstate` (example: `aks_poc.tfstate`)
