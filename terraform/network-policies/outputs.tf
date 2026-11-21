# Outputs de las NetworkPolicies

output "namespace" {
  description = "Namespace leído del state de terraform/ (local.env): debe coincidir con el de los Pods"
  value       = local.env.namespace
}

# US-30 · Denegación por defecto

output "deny_all_name" {
  description = "Nombre de la política de denegación por defecto"
  value       = kubernetes_network_policy_v1.default_deny_all.metadata[0].name
}

output "deny_all_policy_types" {
  description = "Sentidos aislados por la denegación por defecto"
  value       = kubernetes_network_policy_v1.default_deny_all.spec[0].policy_types
}

# # US-31 (web desde el Ingress Controller) y US-32 (SSH al admin desde el host):
# # añadir aquí sus outputs cuando existan las políticas.

# output "web_ingress_name" {
#   description = "Nombre de la política para permitir tráfico desde el Ingress Controller al Pod web"
#   value       = kubernetes_network_policy_v1.web_ingress.metadata[0].name
# }

# output "web_ingress_policy_types" {
#   description = "Sentidos aislados por la política de tráfico desde el Ingress Controller al Pod web"
#   value       = kubernetes_network_policy_v1.web_ingress.spec[0].policy_types
# }

# output "check_command" {
#   description = "Comando para ver las políticas aplicadas en el namespace"
#   value       = "kubectl get networkpolicy -n ${local.env.namespace}"
# }
