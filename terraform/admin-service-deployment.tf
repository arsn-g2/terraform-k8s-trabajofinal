locals {
  admin_labels = {
    app = "admin"
  }
}

resource "kubernetes_deployment_v1" "admin_server" {
  metadata {
    name      = "admin-deployment"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    labels    = local.admin_labels
  }

  spec {
    replicas = var.admin_num_replicas
    selector {
      match_labels = local.admin_labels
    }
    template {
      metadata {
        labels = local.admin_labels
      }
      spec {
        node_selector = {
          "kubernetes.io/hostname" = "k8s-worker1"
        }

        security_context {
          fs_group = "1000"
        }

        container {
          name  = "admin-server"
          image = var.image_admin # dgsgiros/admin-ssh:latest
          port {
            container_port = 22
          }

          # Un fichero por montaje (sub_path): dos Secrets no pueden ocupar el mismo directorio,
          # y así se conserva el ~/.ssh de la imagen (adminuser, 700)
          volume_mount {
            name       = "ssh-admin-private"
            mount_path = "/home/adminuser/.ssh/id_ed25519"
            sub_path   = "id_ed25519"
            read_only  = true
          }
          volume_mount {
            name       = "ssh-admin-authorized"
            mount_path = "/home/adminuser/.ssh/authorized_keys"
            sub_path   = "authorized_keys"
            read_only  = true
          }
        }

        volume {
          name = "ssh-admin-private"
          secret {
            secret_name  = kubernetes_secret_v1.ssh_admin_private.metadata[0].name
            default_mode = "0440"
            items {
              key  = "id_ed25519"
              path = "id_ed25519"
              mode = "0440"
            }
          }
        }

        volume {
          name = "ssh-admin-authorized"
          secret {
            secret_name  = kubernetes_secret_v1.ssh_admin_authorized.metadata[0].name
            default_mode = "0444"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "adm_service" {
  metadata {
    name      = "admin-service"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }
  spec {
    type = "NodePort"

    selector = local.admin_labels # app = "admin"

    port {
      port        = 80
      target_port = 80
      node_port   = 30002
    }

  }
}
