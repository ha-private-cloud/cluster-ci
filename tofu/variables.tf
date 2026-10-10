variable "kubeconfig_path" {
  description = "Path to the Talos cluster's kubeconfig."
  type        = string
  default     = "../../proxmox-tofu/_out/kubeconfig"
}

variable "namespace" {
  description = "Namespace for the runner and its build Jobs."
  type        = string
  default     = "ci"
}

variable "ci_hostname" {
  description = "Hostname the runner API is served on via Ingress."
  type        = string
  default     = "ci.clusterkeep.dev.net"
}

variable "runner_image" {
  description = "Image repository for the runner."
  type        = string
  default     = "registry.clusterkeep.dev.net/ci-runner"
}

variable "runner_image_tag" {
  description = "Image tag to deploy for the runner."
  type        = string
}

variable "runner_replicas" {
  description = "Replica count for the runner."
  type        = number
  default     = 1
}

variable "nexus_docker_hostname" {
  description = "Hostname for Nexus's docker-hosted repo connector."
  type        = string
  default     = "registry.clusterkeep.dev.net"
}

variable "kaniko_image" {
  description = "Kaniko executor image used by build Jobs."
  type        = string
  default     = "gcr.io/kaniko-project/executor:v1.23.2-debug"
}

variable "build_workspace_size" {
  description = "Size of the shared PVC build Jobs use as scratch space for uploaded source."
  type        = string
  default     = "10Gi"
}

variable "build_job_ttl_seconds" {
  description = "Seconds a finished build Job is kept before Kubernetes garbage-collects it."
  type        = number
  default     = 3600
}

variable "max_concurrent_builds" {
  description = "How many builds the runner runs at once."
  type        = number
  default     = 1
}

variable "nexus_ci_username" {
  description = "Username of the Nexus push user for build Jobs."
  type        = string
  sensitive   = true
}

variable "nexus_ci_password" {
  description = "Password of the Nexus push user for build Jobs."
  type        = string
  sensitive   = true
}

variable "ingress_tls_secret_name" {
  description = "Shared TLS secret serving the runner ingress."
  type        = string
  default     = "clusterkeep-tls"
}
