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

    # US-24: la IP de la VLAN es fija (10.1.2.5), así que nunca puede haber dos Pods admin a la vez.
    # Con RollingUpdate (el valor por defecto) el Pod nuevo arranca antes de borrar el viejo
    # y los dos tendrían 10.1.2.5 durante unos segundos. Recreate borra primero el viejo.
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = local.admin_labels

        # US-24: segunda interfaz (net1) en la VLAN 1000 con IP fija (D-005).
        # Multus lee esta anotación, usa la NAD vlan1000-admin (macvlan sobre e2.1000, IPAM static)
        # y le pasa la IP pedida gracias a capabilities.ips. Queda así:
        #   [{"name": "vlan1000-admin", "ips": ["10.1.2.5/24"]}]
        # Referenciar la NAD (y no escribir su nombre) hace que Terraform la cree antes que el Deployment.
        annotations = {
          "k8s.v1.cni.cncf.io/networks" = jsonencode([{
            name = kubernetes_manifest.nad_admin.manifest.metadata.name
            ips  = [local.vlan_admin_cidr]
          }])
        }

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
    # Local: sin SNAT, el Pod ve la IP real del host (10.10.20.2), necesario para el ipBlock de US-32.
    # Solo responde el nodo donde está el Pod (k8s-worker1).
    external_traffic_policy = "Local"

    selector = local.admin_labels # app = "admin"

    port {
      port        = 2222  # ClusterIP del Service (dentro del clúster)
      target_port = 22    # sshd en el contenedor
      node_port   = 30002 # en la IP de cada nodo: ssh -p 30002 adminuser@10.10.10.11
    }

  }
}
