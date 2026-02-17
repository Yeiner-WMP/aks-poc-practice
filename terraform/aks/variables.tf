variable "resource_group_name" {
  type        = string
  description = "Name of the existing Azure Resource Group where AKS will be deployed."
}

variable "aks_name" {
  type        = string
  description = "Name of the AKS cluster."
}

variable "aks_dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS cluster."
}

variable "app_name" {
  type        = string
  description = "Application name used to derive Kubernetes namespace, labels, and resource names."
}

variable "acr_name" {
  type        = string
  description = "Name of the Azure Container Registry. Supplied via workflow TF_VAR_acr_name."
}

variable "image_name" {
  type        = string
  description = "Docker image name (repository) in ACR. Supplied via workflow TF_VAR_image_name."
}

variable "image_tag" {
  type        = string
  description = "Docker image tag (typically the Git SHA). Passed by workflow at plan/apply time."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to Azure resources. Tag keys must remain the same (e.g., \"Owner 1\", \"Owner 2\", \"Client Code\")."
}

variable "default_node_pool_node_count" {
  type        = number
  description = "Number of nodes in the default node pool."
  default     = 1
}

variable "default_node_pool_vm_size" {
  type        = string
  description = "VM size for the default node pool."
  default     = "Standard_DS2_v2"
}
