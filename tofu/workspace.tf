resource "kubernetes_persistent_volume_claim_v1" "build_workspace" {
  metadata {
    name      = "build-workspace"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-csi"

    resources {
      requests = {
        storage = var.build_workspace_size
      }
    }
  }
}
