output "cluster_name" {
  value       = google_container_cluster.this.name
  description = "Cluster name"
}

output "cluster_endpoint" {
  value       = google_container_cluster.this.endpoint
  description = "Cluster API endpoint"
  sensitive   = true
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  description = "Base64-encoded cluster CA certificate"
  sensitive   = true
}

output "location" {
  value       = google_container_cluster.this.location
  description = "Cluster location (zone for zonal)"
}

output "node_pool_name" {
  value       = google_container_node_pool.default.name
  description = "Name of the default node pool"
}
