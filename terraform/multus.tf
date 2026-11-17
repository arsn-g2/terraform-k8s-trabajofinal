# Redes extra de Multus en la VLAN compartida con los LXC (US-11, D-005, D-010)
#
# Las dos NAD son macvlan en modo bridge sobre la subinterfaz e2.1000, que crea
# scripts/setup-vlan-workers.sh en cada arranque. Plan de direcciones de la VLAN:
#   admin      10.1.2.5          IPAM static (la IP la pide el Pod en su anotación)
#   web        10.1.2.10-50      IPAM whereabouts (scripts/setup-whereabouts.sh, D-011)
#   bbdd/logs  10.1.2.100/.101   fijas en vnx/vnx-vm-bdd-logs.xml

locals {
  vlan_master = "${var.vlan_master_if}.${var.vlan_id}"
  # La anotación del admin pide la IP con prefijo: 10.1.2.5/24
  vlan_admin_cidr = "${var.vlan_admin_ip}/${split("/", var.vlan_subnet)[1]}"
}

# Pods web: whereabouts guarda las IPs dadas en un IPPool del clúster,
# así que dos réplicas en workers distintos nunca reciben la misma (US-19, prueba 5)
resource "kubernetes_manifest" "nad_web" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan${var.vlan_id}-web"
      namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        type       = "macvlan"
        master     = local.vlan_master
        mode       = "bridge"
        ipam = {
          type        = "whereabouts"
          range       = var.vlan_subnet
          range_start = var.vlan_web_range_start
          range_end   = var.vlan_web_range_end
        }
      })
    }
  }
}

# Pod admin: IPAM static. Con capabilities.ips, Multus pasa al plugin la IP
# que el Pod pide en la anotación: [{"name": "vlan1000-admin", "ips": ["10.1.2.5/24"]}]
resource "kubernetes_manifest" "nad_admin" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan${var.vlan_id}-admin"
      namespace = kubernetes_namespace_v1.namespace.metadata[0].name
    }
    spec = {
      config = jsonencode({
        cniVersion   = "0.3.1"
        type         = "macvlan"
        master       = local.vlan_master
        mode         = "bridge"
        capabilities = { ips = true }
        ipam = {
          type = "static"
        }
      })
    }
  }
}