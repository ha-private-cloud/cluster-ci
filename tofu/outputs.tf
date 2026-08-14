output "runner_url" {
  description = "URL for the runner API once DNS/hosts is configured."
  value       = "https://${var.ci_hostname}"
}

output "runner_api_token" {
  description = "Bearer token cluster-cli needs. Put it in ~/.config/cluster-cli/config.toml (see README)."
  value       = random_password.runner_api_token.result
  sensitive   = true
}

output "etc_hosts_note" {
  description = "Reminder to map the hostname to a worker node IP."
  value       = "Add to /etc/hosts: '<worker-node-ip> ${var.ci_hostname}' (ingress-nginx runs as a DaemonSet with hostNetwork on the worker nodes)."
}

