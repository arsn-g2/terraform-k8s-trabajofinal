output "web_num_replicas" {
  value = var.web_num_replicas
}


# Valores del escenario (docs/datos-escenario.md §8)

output "group_number" {
  value = var.group_number
}

output "ingress_path" {
  description = "Ruta del Ingress hacia el Service web"
  value       = "/servers-G${var.group_number}"
}

output "image_web" {
  value = var.image_web
}

output "image_admin" {
  value = var.image_admin
}

output "host_user_lan_ip" {
  value = var.host_user_lan_ip
}

output "worker1_ip" {
  value = var.worker1_ip
}

output "ingress_class" {
  value = var.ingress_class
}

output "vlan_master_if" {
  value = var.vlan_master_if
}

output "vlan_id" {
  value = var.vlan_id
}

output "vlan_subnet" {
  value = var.vlan_subnet
}

# output "deployment_name" {
#   value = kubernetes_deployment_v1.web_servers.metadata[0].name
# }
# output "deployment_replicas" {
#   value = kubernetes_deployment_v1.web_servers.spec[0].replicas
# }
# output "service_name" {
#   value = kubernetes_service_v1.web_service.metadata[0].name
# }
# output "service_type" {
#   value = kubernetes_service_v1.web_service.spec[0].type
# }
# output "service_cluster_ip" {
#   value = kubernetes_service_v1.web_service.spec[0].cluster_ip
# }
# output "service_node_port" {
#   value = kubernetes_service_v1.web_service.spec[0].port[0].node_port
# }
