resource "kubernetes_config_map_v1" "web_config" {
  metadata {
    name = "nginx-web-config"
    namespace = var.namespace
  }

  # loads the content of index.html.tpl and replaces the variable group with the value of var.group_number
  data = {
    "index.html" = templatefile("${path.module}/nginx/index.html.tpl", {
      group = var.group_number
    })
  }
}

