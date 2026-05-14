output "network_id" {
  value       = google_compute_network.vpc.id
  description = "VPC network ID"
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "VPC network name"
}

output "subnet_id" {
  value       = google_compute_subnetwork.subnet.id
  description = "Subnet ID"
}

output "subnet_name" {
  value       = google_compute_subnetwork.subnet.name
  description = "Subnet name"
}

output "pods_range_name" {
  value       = "pods"
  description = "Secondary IP range name for Pods"
}

output "services_range_name" {
  value       = "services"
  description = "Secondary IP range name for Services"
}
