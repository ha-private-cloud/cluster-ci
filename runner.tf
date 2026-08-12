resource "kubernetes_deployment_v1" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
    labels = {
      app = "ci-runner"
    }
  }

  spec {
    replicas = var.runner_replicas

    selector {
      match_labels = {
        app = "ci-runner"
      }
    }

    template {
      metadata {
        labels = {
          app = "ci-runner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.runner.metadata[0].name

        # Makes the NFS-backed build-workspace PVC writable by the runner's
        # uid 1000 (appuser, see runner/Dockerfile) — same fix as
        # cluster-auth/postgres.tf's fs_group, same underlying csi-driver-nfs
        # fsGroupPolicy=File mechanism.
        security_context {
          fs_group = 1000
        }

        container {
          name  = "runner"
          image = "${var.runner_image}:${var.runner_image_tag}"

          port {
            name           = "http"
            container_port = 5000
          }

          env {
            name  = "NAMESPACE"
            value = var.namespace
          }

          env {
            name  = "NEXUS_DOCKER_HOSTNAME"
            value = var.nexus_docker_hostname
          }

          env {
            name  = "KANIKO_IMAGE"
            value = var.kaniko_image
          }

          env {
            name  = "HELM_IMAGE"
            value = var.helm_image
          }

          env {
            name  = "BUILD_JOB_TTL_SECONDS"
            value = tostring(var.build_job_ttl_seconds)
          }

          env {
            name  = "MAX_CONCURRENT_BUILDS"
            value = tostring(var.max_concurrent_builds)
          }

          env {
            name  = "BUILD_SERVICE_ACCOUNT"
            value = kubernetes_service_account.build.metadata[0].name
          }

          env {
            name  = "DEPLOY_SERVICE_ACCOUNT"
            value = kubernetes_service_account.deploy.metadata[0].name
          }

          env {
            name  = "NEXUS_CREDENTIALS_SECRET"
            value = kubernetes_secret.nexus_ci_push_credentials.metadata[0].name
          }

          env {
            name  = "WORKSPACE_PVC"
            value = kubernetes_persistent_volume_claim_v1.build_workspace.metadata[0].name
          }

          env {
            name = "API_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.runner_api_token.metadata[0].name
                key  = "token"
              }
            }
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.build_workspace.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  spec {
    selector = {
      app = "ci-runner"
    }

    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "runner" {
  metadata {
    name      = "ci-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.ci_hostname

      http {
        path {
          path      = "/"
          path_type = "ImplementationSpecific"

          backend {
            service {
              name = kubernetes_service_v1.runner.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    # No secretName: falls back to ingress-nginx's default self-signed cert,
    # same as registry.talos.lab/nexus.talos.lab — only auth.talos.lab needs
    # its own cert, because OIDC hostname verification has no skip-verify option.
    tls {
      hosts = [var.ci_hostname]
    }
  }
}
