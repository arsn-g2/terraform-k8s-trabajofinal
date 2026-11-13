resource "kubernetes_network_policy_v1" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress"
    namespace = "default"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "nginx"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "tester"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # ICMP: NetworkPolicy cannot match ICMP, so this rule has no ports and
    # therefore allows every protocol/port (incl. ping) from the tester pod
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "tester"
          }
        }
      }
    }
  }
}

output "nginx_ingress_policy_id" {
  description = "Terraform ID of the nginx ingress policy (namespace/name)"
  value       = kubernetes_network_policy_v1.nginx_ingress.id
}
output "nginx_ingress_policy_types" {
  description = "Traffic directions the policy applies to"
  value       = join(", ", kubernetes_network_policy_v1.nginx_ingress.spec[0].policy_types)
}
output "nginx_ingress_pod_selector" {
  description = "Labels of the pods the policy applies to"
  value = join(",", [
    for k, v in kubernetes_network_policy_v1.nginx_ingress.spec[0].pod_selector[0].match_labels : "${k}=${v}"
  ])
}
output "nginx_ingress_allowed_sources" {
  description = "Pod labels allowed to send traffic to the selected pods"
  value = flatten([
    for rule in kubernetes_network_policy_v1.nginx_ingress.spec[0].ingress : [
      for peer in rule.from : [
        for sel in peer.pod_selector : join(",", [for k, v in sel.match_labels : "${k}=${v}"])
      ]
    ]
  ])
}
output "nginx_ingress_allowed_ports" {
  description = "Allowed ingress ports as protocol/port"
  value = flatten([
    for rule in kubernetes_network_policy_v1.nginx_ingress.spec[0].ingress : [
      for p in rule.ports : "${p.protocol}/${p.port}"
    ]
  ])
}
