resource "kubernetes_config_map_v1" "web_config" {
  metadata {
    name      = "nginx-web-config"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }

  # loads the content of index.html.tpl and replaces the variable group with the value of var.group_number
  data = {
    "index.html" = templatefile("${path.module}/templates/index.html.tpl", {
      group = var.group_number
    })
  }
}

# Pod
# ├── volume "template"  ← ConfigMap (index.html with __POD_NAME__)
# ├── volume "html"      ← emptyDir (empty, writable, lives as long as the Pod)
# │
# ├── container "page-generator" (sidecar)
# │     reads /template/index.html  →  sed  →  writes /html/index.html  →  sleep infinity
# │
# └── container "nginx-server"
#       serves the "html" volume from its root folder
