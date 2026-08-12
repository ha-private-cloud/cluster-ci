# The runner's own identity: creates/watches build & deploy Jobs and reads
# their pods' logs to stream back to ci-cli. Scoped to its own namespace only.
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

  # Kubernetes RBAC treats subresources as distinct resource names — the
  # rule above doesn't implicitly cover jobs/status, which the client needs
  # to poll a Job's completion state.
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

# Identity for the test+build+push Job. Deliberately granted zero Kubernetes
# API permissions — it only runs pytest and Kaniko (a registry push, not a
# k8s API call), so it never needs to touch the cluster API at all.
resource "kubernetes_service_account" "build" {
  metadata {
    name      = "ci-build"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

# Identity for the deploy Job (`helm upgrade`). A ClusterRole so its verb/
# resource list is reusable across apps, but NOT bound cluster-wide here —
# each app repo binds it in its own namespace (see clusterkeep-ui.tf for the
# first example), same as how cluster-rbac treats "who can touch this
# namespace" as that namespace-owning repo's job, not a central one.
resource "kubernetes_service_account" "deploy" {
  metadata {
    name      = "ci-deploy"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "deploy" {
  metadata {
    name = "ci-deploy"
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets", "serviceaccounts", "pods"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}
