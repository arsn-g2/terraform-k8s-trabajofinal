# Namespace dedicado al escenario (D-002)
resource "kubernetes_namespace_v1" "namespace" {
  metadata {
    name = var.namespace
  }
}
