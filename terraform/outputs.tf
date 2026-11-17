output "namespace" {
  description = "Namespace de todos los recursos (D-002)"
  value       = kubernetes_namespace_v1.namespace.metadata[0].name
}

output "web_num_replicas" {
  value = var.web_num_replicas
}


# Valores del escenario (docs/datos-escenario.md §8)

output "group_number" {
  value = var.group_number
}


output "image_web" {
  value = var.image_web
}

output "image_admin" {
  value = var.image_admin
}

# output "host_user_lan_ip" {
#   value = var.host_user_lan_ip
# }
#
# output "worker1_ip" {
#   value = var.worker1_ip
# }
#
# output "ingress_class" {
#   value = var.ingress_class
# }
#
# output "vlan_master_if" {
#   value = var.vlan_master_if
# }
#
# output "vlan_id" {
#   value = var.vlan_id
# }
#
# output "vlan_subnet" {
#   value = var.vlan_subnet
# }

# Web (US-13, US-14, US-15)

output "web_config_map_name" {
  description = "ConfigMap con la plantilla index.html"
  value       = kubernetes_config_map_v1.web_config.metadata[0].name
}

output "web_labels" {
  description = "Labels de los Pods web: las usan el Service y las NetworkPolicies de C"
  value       = local.web_labels
}

output "web_deployment_name" {
  value = kubernetes_deployment_v1.web_servers.metadata[0].name
}
output "web_deployment_replicas" {
  value = kubernetes_deployment_v1.web_servers.spec[0].replicas
}
output "web_service_name" {
  value = kubernetes_service_v1.web_service.metadata[0].name
}
output "web_service_type" {
  value = kubernetes_service_v1.web_service.spec[0].type
}
output "web_service_cluster_ip" {
  value = kubernetes_service_v1.web_service.spec[0].cluster_ip
}
# Solo tiene sentido mientras el Service sea NodePort (US-15 lo cambia a ClusterIP)
# output "web_service_node_port" {
#   value = kubernetes_service_v1.web_service.spec[0].port[0].node_port
# }

# Ingress y MetalLB (US-15)

locals {
  # IP que MetalLB da al Service del Ingress Controller; null mientras esté <pending>
  ingress_lb_ip = try(data.kubernetes_service_v1.ingress_controller.status[0].load_balancer[0].ingress[0].ip, null)
  # NodePort del puerto http del controller (alternativa si no hay IP de MetalLB)
  ingress_http_node_port = one([for p in data.kubernetes_service_v1.ingress_controller.spec[0].port : p.node_port if p.name == "http"])
}

output "ingress_name" {
  value = kubernetes_ingress_v1.web_ingress.metadata[0].name
}

output "ingress_class" {
  value = kubernetes_ingress_v1.web_ingress.spec[0].ingress_class_name
}

output "ingress_path" {
  description = "Ruta del Ingress hacia el Service web (D-001)"
  value       = var.g2_ingress_path
}

output "ingress_lb_ip" {
  description = "IP externa del Ingress Controller asignada por MetalLB (null = <pending>)"
  value       = local.ingress_lb_ip
}

output "ingress_http_node_port" {
  description = "NodePort http del Ingress Controller"
  value       = local.ingress_http_node_port
}

output "metallb_pool_addresses" {
  description = "Rangos del IPAddressPool de MetalLB"
  value       = data.kubernetes_resource.metallb_pool.object.spec.addresses
}

output "web_url" {
  description = "URL para probar la web: por la IP de MetalLB o, si no hay, por el NodePort en worker1"
  value = (local.ingress_lb_ip != null
    ? "http://${local.ingress_lb_ip}${var.g2_ingress_path}"
  : "http://10.10.10.11:${local.ingress_http_node_port}${var.g2_ingress_path}")
}

# Admin (US-17, US-18)

output "admin_labels" {
  description = "Labels del Pod admin"
  value       = local.admin_labels
}

output "admin_deployment_name" {
  value = kubernetes_deployment_v1.admin_server.metadata[0].name
}
output "admin_deployment_replicas" {
  value = kubernetes_deployment_v1.admin_server.spec[0].replicas
}
output "admin_service_name" {
  value = kubernetes_service_v1.adm_service.metadata[0].name
}
output "admin_service_type" {
  value = kubernetes_service_v1.adm_service.spec[0].type
}
output "admin_service_node_port" {
  description = "Puerto para el SSH al admin: 10.10.10.11:<node_port>"
  value       = kubernetes_service_v1.adm_service.spec[0].port[0].node_port
}
