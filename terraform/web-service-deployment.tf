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
        # US-22: Multus añade net1 en la VLAN con la NAD[NetworkAttachmentDefinition] de (whereabouts).
        # Va en el template porque Multus lee las anotaciones del Pod, no las del Deployment.
        # Referenciar la NAD (y no escribir "vlan1000-web") hace que Terraform la cree antes.
        annotations = {
          "k8s.v1.cni.cncf.io/networks" = kubernetes_manifest.nad_web.manifest.metadata.name
        }
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

          # Mount the pair 1 public key as webuser's authorized_keys, so the admin can SSH in (US-17)
          # sub_path mounts a single file and keeps the image's ~/.ssh (webuser, 700)
          volume_mount {
            name       = "ssh-web-authorized"
            mount_path = "/home/webuser/.ssh/authorized_keys"
            sub_path   = "authorized_keys"
            read_only  = true
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

        // Mount the ssh-web-authorized Secret as a volume: one Secret for the 3 web Pods (US-17, D-004)
        volume {
          name = "ssh-web-authorized"
          secret {
            secret_name  = kubernetes_secret_v1.ssh_web_authorized.metadata[0].name
            default_mode = "0444"
          }
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
    type     = "ClusterIP"
    selector = local.web_labels # app = "web"

    port {
      port        = 8080
      target_port = 80
      # node_port   = 30001
    }

  }
}
