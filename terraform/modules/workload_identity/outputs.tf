output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Full resource name of the WIF provider (used in GitHub Actions)"
}

output "deployer_sa_email" {
  value       = google_service_account.deployer.email
  description = "Email of the deployer Service Account"
}

output "pool_name" {
  value       = google_iam_workload_identity_pool.github.name
  description = "Full resource name of the WIF pool"
}
