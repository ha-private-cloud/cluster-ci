# Bearer token ci-cli authenticates with. Static token, not OIDC/Authentik —
# this is a single-user homelab, the runner is only reachable on the LAN, and
# Authentik is currently wired for browser redirect flows only; wiring
# device-code or client-credentials auth for one trusted CLI caller isn't
# worth the added complexity. Same random_password -> kubernetes_secret
# pattern used throughout this project (see cluster-auth).
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
