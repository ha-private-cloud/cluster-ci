# Shared scratch space between the runner (writer: unpacks each build's
# uploaded source tarball into a per-build subdirectory) and its Jobs
# (reader: mount the same subdirectory as their build context). ReadWriteMany
# is required because the runner and Job pods run concurrently and need to
# see the same files , nfs-csi is the only StorageClass in this cluster that
# supports it (see cluster-config's csi-driver-nfs install).
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
