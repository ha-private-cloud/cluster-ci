# Backstop against runaway resource use. This is the first repo in the
# project whose whole job is spawning ephemeral Jobs repeatedly (everything
# else here is "apply once, long-running") and the first ResourceQuota
# anywhere in the cluster , worker node talos-c94-oxe is already close to its
# memory limit ceiling (it runs Nexus), so builds need a hard ceiling, not
# just good intentions in the Job specs.
resource "kubernetes_resource_quota" "ci" {
  metadata {
    name      = "ci-quota"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  spec {
    hard = {
      "pods"                   = "10"
      "requests.cpu"           = "2"
      "requests.memory"        = "4Gi"
      "limits.cpu"             = "4"
      "limits.memory"          = "6Gi"
      "persistentvolumeclaims" = "2"
    }
  }
}
