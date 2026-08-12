resource "kubernetes_namespace" "ci" {
  metadata {
    name = var.namespace
  }
}
