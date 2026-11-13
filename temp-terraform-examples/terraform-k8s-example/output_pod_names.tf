data "kubernetes_resources" "nginx_pods" {
  api_version    = "v1"
  kind           = "Pod"
  label_selector = "app=nginx"
  depends_on = [
    kubernetes_deployment_v1.web_servers
  ]
}
output "nginx_pod_names" {
  value = [
    for pod in data.kubernetes_resources.nginx_pods.objects : pod.metadata.name
  ]
}
