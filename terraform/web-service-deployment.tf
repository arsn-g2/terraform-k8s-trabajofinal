locals {
  web_labels = {
    app = "nginx"
  }
}

resource "kubernetes_deployment_v1" "web_servers" {
  metadata {
    name   = "nginx-deployment"
    labels = local.web_labels    #app = "nginx"
  }

  spec {
    replicas = var.web_num_replicas
    selector {
      match_labels = local.web_labels  # app = "nginx"
    }
    template {
      metadata {
        labels = local.web_labels  # app = "nginx"
      }
      spec {
        container {
          name  = "nginx-server"
          image = var.image_web # dgsgiros/nginx-ssh:latest
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "web_service" {
  metadata {
    name = "nginx-service"
  }
  spec {
    type = "NodePort"

    selector = local.web_labels     # app = "nginx"

    port {
      port        = 80
      target_port = 80
      node_port   = 30001
    }

  }
}
