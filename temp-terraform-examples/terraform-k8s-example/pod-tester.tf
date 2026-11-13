resource "kubernetes_pod_v1" "tester" {
  metadata {
    name      = "tester"
    namespace = "default"

    labels = {
      app = "tester"
    }
  }

  spec {
    container {
      name    = "tester"
      image   = "dougbtv/centos-network"
      command = ["sleep", "3600"]
    }
  }
}

