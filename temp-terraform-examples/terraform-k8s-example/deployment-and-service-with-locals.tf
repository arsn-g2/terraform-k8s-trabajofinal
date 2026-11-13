locals {
  web_labels = {
    app = "nginx"
  }
}

resource "kubernetes_deployment_v1" "web_servers" {
  metadata {
    name   = "nginx-deployment"
    labels = local.web_labels
  }

  spec {
    replicas = 3
    selector {
      match_labels = local.web_labels
    }
    template {
      metadata {
        labels = local.web_labels
      }
      spec {
        container {
          name  = "nginx-server"
          image = "nginx"
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

    selector = local.web_labels

    port {
      port        = 80
      target_port = 80
      node_port   = 30001
    }

  }
}
