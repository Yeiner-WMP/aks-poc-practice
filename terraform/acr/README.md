# Azure Container Registry (ACR) Terraform

This Terraform configuration deploys an **Azure Container Registry (ACR)** into an **existing Azure Resource Group**.

- The Resource Group is **not created** here; it is looked up via a Terraform data source (`data.azurerm_resource_group`).
- This module intentionally defines **no Terraform outputs**.

## Resources

- `azurerm_container_registry` — creates the container registry.

## Inputs

| Name | Type | Required | Default | Source | Description |
|------|------|----------|---------|--------|-------------|
| `resource_group_name` | `string` | Yes | n/a | `vars/<env>.tfvars` | Name of the existing Azure Resource Group where the ACR will be deployed. |
| `acr_name` | `string` | Yes | n/a | Workflow env (`TF_VAR_acr_name`) | Name of the Azure Container Registry. In GitHub Actions, this is sourced from the repo variable `ACR_NAME`. |
| `tags` | `map(string)` | Yes | n/a | `vars/<env>.tfvars` | Tags applied to the ACR. The existing tag keys (e.g., `"Owner 1"`, `"Owner 2"`, `"Client Code"`) are expected to remain the same. |
| `acr_sku` | `string` | No | `Basic` | Terraform default | ACR SKU tier (e.g., `Basic`, `Standard`, `Premium`). |

## State

This module uses an **AzureRM remote backend**. Backend configuration is supplied at runtime by the GitHub Actions workflow.

State key convention used by the workflow:

- `acr_<environment>.tfstate` (example: `acr_poc.tfstate`)

## Outputs

None (by design).
