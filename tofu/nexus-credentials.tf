resource "kubernetes_secret" "nexus_ci_push_credentials" {
  metadata {
    name      = "nexus-ci-push-credentials"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.nexus_docker_hostname) = {
          username = var.nexus_ci_username
          password = var.nexus_ci_password
          auth     = base64encode("${var.nexus_ci_username}:${var.nexus_ci_password}")
        }
      }
    })
  }
}
