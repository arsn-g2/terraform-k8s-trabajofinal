variable "temp" {
  type    = string
  default = "a"

}
# # US-31 · Permitir tráfico desde el Ingress Controller al Pod web
# resource "kubernetes_network_policy_v1" "web_ingress" {
#   metadata {
#     name      = "web-ingress"
#     namespace = local.env.namespace
#   }
#   spec {
#     # ingress TO this pods (app = "web") FROM the Ingress Controller (ingress-nginx/Pod controller)(below)
#     pod_selector {
#       match_labels = local.env.web_labels # app = "web"
#     }
#     policy_types = ["Ingress"]
#     # Tráfico entrante permitido desde el Ingress Controller.
#     # No hace falta regla de egress para las respuestas: Calico sigue las conexiones y,
#     # si la conexión entrante está permitida, su respuesta también.
#     ingress {
#       # namespace_selector y pod_selector en el MISMO from = AND:
#       # solo los Pods del controller dentro del namespace ingress-nginx.
#       from {
#         namespace_selector {
#           match_labels = {
#             "kubernetes.io/metadata.name" = "ingress-nginx"
#           }
#         }

#         # ingress FROM this pods (this is an AND. 
#         # (controller Pod must be in the namespace ingress-nginx AND have these labels))
#         pod_selector {
#           match_labels = {
#             "app.kubernetes.io/name"      = "ingress-nginx"
#             "app.kubernetes.io/component" = "controller"
#           }
#         }
#       }
#       # El controller envía el tráfico directamente al puerto 80 del Pod web, no al 8080 del Service.
#       # El provider espera un string; Kubernetes acepta número o string.
#       ports {
#         protocol = "TCP"
#         port     = "80"
#       }
#     }
#   }
# }
