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
