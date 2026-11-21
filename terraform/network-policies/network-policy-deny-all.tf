# US-30 · Política de denegación por defecto (enunciado §5.1)
#
# pod_selector {} vacío = selecciona TODOS los Pods del namespace (web y admin).
# Con Ingress y Egress y sin bloques ingress {} ni egress {}, quedan aislados en los dos
# sentidos: no entra ni sale nada por eth0. Las políticas de US-31 y US-32 se suman a esta
# y abren solo lo necesario.
# Calico no filtra net1 (macvlan): el tráfico de la VLAN sigue pasando (US-33).
resource "kubernetes_network_policy_v1" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = local.env.namespace
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}