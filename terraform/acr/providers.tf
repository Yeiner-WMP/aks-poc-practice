terraform {
  required_version = "= 1.11.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.60.0"
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
