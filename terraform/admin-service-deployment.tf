locals {
  admin_labels = {
    app = "admin"
  }
}

resource "kubernetes_deployment_v1" "admin_server" {
  metadata {
    name   = "admin-deployment"
    labels = local.admin_labels    #app = "admin"
  }

  spec {
    replicas = var.admin_num_replicas
    selector {
      match_labels = local.admin_labels  # app = "admin"
    }
    template {
      metadata {
        labels = local.admin_labels  # app = "admin"
      }
      spec {
        container {
          name  = "admin-server"
          image = var.image_admin # dgsgiros/admin-ssh:latest
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "adm_service" {
  metadata {
    name = "admin-service"
  }
  spec {
    type = "NodePort"

    selector = local.admin_labels     # app = "admin"

    port {
      port        = 80
      target_port = 80
      node_port   = 30002
    }

  }
}
