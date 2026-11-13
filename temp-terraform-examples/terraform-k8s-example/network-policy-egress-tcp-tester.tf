resource "kubernetes_network_policy_v1" "tester_egress" {
  metadata {
    name      = "tester-egress"
    namespace = "default"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "tester"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        pod_selector {
          match_labels = {
            app = "nginx"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # DNS: allow name resolution through CoreDNS in kube-system
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    # ICMP: NetworkPolicy cannot match ICMP, so this rule has no ports and
    # therefore allows every protocol/port (incl. ping) to the nginx pods
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "nginx"
          }
        }
      }
    }
  }
}

output "tester_egress_policy_id" {
  description = "Terraform ID of the tester egress policy (namespace/name)"
  value       = kubernetes_network_policy_v1.tester_egress.id
}
output "tester_egress_policy_types" {
  description = "Traffic directions the policy applies to"
  value       = join(", ", kubernetes_network_policy_v1.tester_egress.spec[0].policy_types)
}
output "tester_egress_pod_selector" {
  description = "Labels of the pods the policy applies to"
  value = join(",", [
    for k, v in kubernetes_network_policy_v1.tester_egress.spec[0].pod_selector[0].match_labels : "${k}=${v}"
  ])
}
output "tester_egress_rules" {
  description = "One line per egress rule: destination -> allowed protocol/ports"
  value = [
    for rule in kubernetes_network_policy_v1.tester_egress.spec[0].egress : format("%s -> %s",
      join(" | ", [
        for peer in rule.to : join(" ", concat(
          [for ns in peer.namespace_selector : "ns(${join(",", [for k, v in coalesce(ns.match_labels, {}) : "${k}=${v}"])})"],
          [for sel in peer.pod_selector : "pod(${join(",", [for k, v in coalesce(sel.match_labels, {}) : "${k}=${v}"])})"]
        ))
      ]),
      length(coalesce(rule.ports, [])) == 0 ? "all protocols/ports" : join(",", [for p in rule.ports : "${p.protocol}/${p.port}"])
    )
  ]
}
