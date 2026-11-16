locals {
  web_labels = {
    app = "web"
  }
}

resource "kubernetes_deployment_v1" "web_servers" {
  metadata {
    name      = "nginx-deployment"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    labels    = local.web_labels #app = "web"
  }

  spec {
    replicas = var.web_num_replicas
    selector {
      match_labels = local.web_labels # app = "web"
    }
    template {
      metadata {
        labels = local.web_labels # app = "web"
      }
      spec {
        container {
          name  = "nginx-server"
          image = var.image_web # dgsgiros/nginx-ssh:latest
          port {
            container_port = 80
          }

          # Mount the ConfigMap at /etc/nginx
          volume_mount {
            name       = "html-sidecar-update"
            mount_path = "/usr/share/nginx/html"
            # sub_path   = " - "  # Mount a single file, not the whole dir
            read_only = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        // Mount the ConfigMap as a volume
        volume {
          name = "nginx-web-template"
          config_map {
            name = kubernetes_config_map_v1.web_config.metadata[0].name

          }
        }

        // Mount an emptyDir volume for the generated HTML to be updated by the sidecar container
        volume {
          name = "html-sidecar-update"
          empty_dir {}
        }

        // Sidecar container to generate the HTML file with the pod name
        container {
          name  = "page-updater-sidecar"
          image = var.image_web

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          command = ["sh", "-c", "sed \"s/__POD_NAME__/$POD_NAME/g\" /template/index.html > /html/index.html && sleep infinity"]

          volume_mount {
            name       = "nginx-web-template"
            mount_path = "/template"
            read_only  = true
          }
          volume_mount {
            name       = "html-sidecar-update"
            mount_path = "/html"
          }
        }

      }



    }
  }
}

resource "kubernetes_service_v1" "web_service" {
  metadata {
    name      = "nginx-service"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }
  spec {
    type = "NodePort"

    selector = local.web_labels # app = "web"

    port {
      port        = 80
      target_port = 80
      node_port   = 30001
    }

  }
}
