output "deployment_name" {
  value = kubernetes_deployment_v1.web_servers.metadata[0].name
}
output "deployment_replicas" {
  value = kubernetes_deployment_v1.web_servers.spec[0].replicas
}
output "service_name" {
  value = kubernetes_service_v1.web_service.metadata[0].name
}
output "service_type" {
  value = kubernetes_service_v1.web_service.spec[0].type
}
output "service_cluster_ip" {
  value = kubernetes_service_v1.web_service.spec[0].cluster_ip
}
output "service_node_port" {
  value = kubernetes_service_v1.web_service.spec[0].port[0].node_port
}
