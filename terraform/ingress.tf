resource "kubernetes_ingress_v1" "web_ingress" {
  metadata {
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    name      = "g2-ingress"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = var.ingress_class

    rule {
      http {
        path {
          path      = var.g2_ingress_path
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.web_service.metadata[0].name // "nginx-service"
              port {
                number = 8080
              }
            }
          }


        }
      }
    }

    # tls {
    #   secret_name = "tls-secret"
    # }
  }
}

# Lecturas (no crean nada) del Ingress Controller y de MetalLB, solo para los outputs de US-15.
# Se leen en cada plan/apply: si MetalLB asigna la IP después, `terraform apply -refresh-only` la actualiza.

# Service LoadBalancer del Ingress Controller: MetalLB le pone la IP externa
data "kubernetes_service_v1" "ingress_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# Pool de MetalLB (CRD, sin recurso nativo en el provider)
data "kubernetes_resource" "metallb_pool" {
  api_version = "metallb.io/v1beta1"
  kind        = "IPAddressPool"
  metadata {
    name      = "default-pool"
    namespace = "metallb-system"
  }
}
