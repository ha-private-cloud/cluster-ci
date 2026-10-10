resource "kubernetes_service_account" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

resource "kubernetes_role" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs/status"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.runner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner.metadata[0].name
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

resource "kubernetes_service_account" "build" {
  metadata {
    name      = "ci-build"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}
