# Kaniko reads this directly as a Docker config (mounted at
# /kaniko/.docker/config.json by the runner's Job manifest , see runner/jobs.py).
# Credentials for the "ci" Nexus user are provisioned manually, not by
# Terraform: Nexus's REST API has no idempotent way to create a user (unlike
# cluster-auth/users.tf's recovery-link POST, which is safe to re-run, a user
# creation POST fails with a 400 on every plan/apply after the first one) ,
# see README for the one-time setup step.
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
