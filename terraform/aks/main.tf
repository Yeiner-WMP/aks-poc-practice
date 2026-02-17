# Look up the existing resource group
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Look up the existing ACR by name, this avoids coupling AKS to the ACR Terraform state
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = data.azurerm_resource_group.rg.name
}

locals {
  # ACR login server can be derived from the registry name
  # The suffix is stable for Azure Container Registry
  acr_login_server = "${var.acr_name}.azurecr.io"

  # The AKS workflow pushes an image tagged with the Git SHA
  # Terraform deploys that same tag by receiving image_tag at runtime
  image            = "${local.acr_login_server}/${var.image_name}:${var.image_tag}"

  # Derive Kubernetes naming from a single app_name input
  k8s_namespace       = var.app_name
  k8s_app_label       = var.app_name
  k8s_deployment_name = "${var.app_name}-app"
  k8s_service_name    = "${var.app_name}-service"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = var.aks_dns_prefix

  # Single node pool for a minimal learning setup
  default_node_pool {
    name            = "default"
    node_count      = var.default_node_pool_node_count
    vm_size         = var.default_node_pool_vm_size

    # Tags are provided as a single map variable
    tags            = var.tags
  }

  # System assigned identity keeps auth simple for a learning repo
  identity {
    type = "SystemAssigned"
  }

  # Tags are provided as a single map variable
  tags                = var.tags
}

# Allow the cluster kubelet identity to pull from the ACR
# Without this, pods will fail to pull private images
resource "azurerm_role_assignment" "this" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = data.azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

resource "kubernetes_namespace_v1" "hello_world_ns" {
  depends_on = [azurerm_role_assignment.this]  # Ensure ACR pull permissions exist before creating Kubernetes objects
  metadata {
    name = local.k8s_namespace
  }
}

resource "kubernetes_deployment_v1" "hello_world_app" {
  depends_on = [azurerm_role_assignment.this]
  metadata {
    name      = local.k8s_deployment_name
    namespace = kubernetes_namespace_v1.hello_world_ns.metadata[0].name
    labels = {
      app = local.k8s_app_label
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.k8s_app_label
      }
    }

    template {
      metadata {
        labels = {
          app = local.k8s_app_label
        }
      }

      spec {
        container {
          # Keep the container name derived from the namespace for clarity
          name  = "${local.k8s_namespace}-container"
          image = local.image
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          # Probes make rollouts more stable and help Kubernetes detect failures
          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "hello_world_service" {
  depends_on = [azurerm_role_assignment.this]
  metadata {
    name      = local.k8s_service_name
    namespace = kubernetes_namespace_v1.hello_world_ns.metadata[0].name
  }

  spec {
    selector = {
      app = local.k8s_app_label
    }

    # LoadBalancer requests a public endpoint from the cloud provider
    type = "LoadBalancer"

    port {
      port        = 80
      target_port = 8080
    }
  }
}
