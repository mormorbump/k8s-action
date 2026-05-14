output "cluster_name" {
  value       = module.gke.cluster_name
  description = "GKE cluster name"
}

output "cluster_location" {
  value       = module.gke.location
  description = "GKE cluster location (zone)"
}

output "cluster_endpoint" {
  value       = module.gke.cluster_endpoint
  description = "GKE cluster endpoint"
  sensitive   = true
}

output "artifact_registry_url" {
  value       = module.artifact_registry.repository_url
  description = "Artifact Registry repository URL"
}

output "workload_identity_provider" {
  value       = module.workload_identity.workload_identity_provider
  description = "WIF provider resource name (use in GitHub Actions)"
}

output "deployer_sa_email" {
  value       = module.workload_identity.deployer_sa_email
  description = "Deployer Service Account email"
}

output "network_name" {
  value       = module.network.network_name
  description = "VPC network name (referenced by istio env)"
}

output "subnet_name" {
  value       = module.network.subnet_name
  description = "Subnet name"
}
