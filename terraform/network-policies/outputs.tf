# Outputs de las NetworkPolicies .

output "namespace" {
  description = "Namespace leído del state de terraform/ (local.env): debe coincidir con el de los Pods"
  value       = local.env.namespace
}


