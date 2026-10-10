resource "random_password" "runner_api_token" {
  length  = 40
  special = false
}

resource "kubernetes_secret" "runner_api_token" {
  metadata {
    name      = "runner-api-token"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  data = {
    token = random_password.runner_api_token.result
  }
}
