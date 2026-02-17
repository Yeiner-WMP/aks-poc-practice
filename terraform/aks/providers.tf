terraform {
  required_version = "= 1.11.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }

  backend "azurerm" {
    # Backend settings (RG, storage account, container, and key) are supplied by the GitHub Actions workflow at terraform init time
    use_oidc = true
  }
}

provider "azurerm" {
  # Auth is provided via GitHub OIDC and ARM environment variables in the workflow
  # This keeps provider configuration out of Terraform code
  features {}
  use_oidc = true
}

provider "kubernetes" {
  # Configure the Kubernetes provider using the kubeconfig values from the AKS resource
  # This allows Terraform to create Kubernetes resources right after the cluster is created
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}
