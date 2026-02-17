variable "resource_group_name" {
  type        = string
  description = "Name of the existing Azure Resource Group where the ACR will be deployed."
}

variable "acr_name" {
  type        = string
  description = "Name of the Azure Container Registry."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources. Tag keys must remain the same (e.g., \"Owner 1\", \"Owner 2\", \"Client Code\")."
}

variable "acr_sku" {
  type        = string
  description = "SKU tier for the Azure Container Registry."
  default     = "Basic"
}
