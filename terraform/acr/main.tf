# Look up the existing resource group
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azurerm_container_registry" "hello_world" {
  # ACR name is injected via workflow TF_VAR_acr_name
  # This avoids duplicating the registry name in tfvars
  name                = var.acr_name

  # Deploy into the existing resource group and inherit its location
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  # Default is Basic unless overridden by setting acr_sku
  sku                 = var.acr_sku

  # Tags are provided as a single map variable
  tags = var.tags
}
