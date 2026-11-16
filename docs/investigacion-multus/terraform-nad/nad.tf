resource "kubernetes_manifest" "vlan1000_tf" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan1000-tf"
      namespace = "multus-poc"
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        type       = "macvlan"
        master     = "e2.1000"
        mode       = "bridge"
        ipam = {
          type        = "whereabouts"
          range       = "10.1.2.0/24"
          range_start = "10.1.2.10"
          range_end   = "10.1.2.50"
        }
      })
    }
  }
}