output "runner_url" {
  description = "URL for the runner API once DNS/hosts is configured."
  value       = "https://${var.ci_hostname}"
}

output "runner_api_token" {
  description = "Bearer token ci-cli needs. Put it in ~/.config/ci-cli/config.toml (see README)."
  value       = random_password.runner_api_token.result
  sensitive   = true
}

output "etc_hosts_note" {
  description = "Reminder to map the hostname to a worker node IP."
  value       = "Add to /etc/hosts: '<worker-node-ip> ${var.ci_hostname}' (ingress-nginx runs as a DaemonSet with hostNetwork on the worker nodes)."
}

output "deploy_cluster_role_name" {
  description = "Name of the ClusterRole app repos bind in their own namespace to let the deploy Job run `helm upgrade` there (see clusterkeep-ui.tf for the first example)."
  value       = kubernetes_cluster_role.deploy.metadata[0].name
}

output "deploy_service_account" {
  description = "Namespace/name of the deploy Job's ServiceAccount, used as the subject when an app repo adds its RoleBinding."
  value = {
    name      = kubernetes_service_account.deploy.metadata[0].name
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}
