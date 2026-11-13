resource "kubernetes_network_policy_v1" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = "default"
  }

  spec {
    pod_selector {}

    policy_types = [
      "Ingress",
      "Egress"
    ]
  }
}

output "deny_all_policy_id" {
  description = "Terraform ID of the deny-all policy (namespace/name)"
  value       = kubernetes_network_policy_v1.default_deny_all.id
}
# output "deny_all_policy_name" {
#   value = kubernetes_network_policy_v1.default_deny_all.metadata[0].name
# }
output "deny_all_policy_namespace" {
  value = kubernetes_network_policy_v1.default_deny_all.metadata[0].namespace
}
# output "deny_all_policy_uid" {
#   description = "UID assigned by the Kubernetes API server"
#   value       = kubernetes_network_policy_v1.default_deny_all.metadata[0].uid
# }
output "deny_all_policy_types" {
  description = "Traffic directions the policy applies to"
  value       = join(", ", kubernetes_network_policy_v1.default_deny_all.spec[0].policy_types)
}
output "deny_all_pod_selector" {
  description = "Pods affected (empty selector = every pod in the namespace)"
  value = (
    length(coalesce(kubernetes_network_policy_v1.default_deny_all.spec[0].pod_selector[0].match_labels, {})) == 0
    ? "all pods in namespace"
    : jsonencode(kubernetes_network_policy_v1.default_deny_all.spec[0].pod_selector[0].match_labels)
  )
}


# kubectl get networkpolicy
# kubectl describe networkpolicy default-deny-all
