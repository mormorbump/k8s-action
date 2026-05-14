variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "github_owner" {
  type        = string
  description = "GitHub user or organization (e.g., mormorbump)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (e.g., k8s-action)"
}

variable "pool_id" {
  type        = string
  description = "Workload Identity Pool ID"
  default     = "github-pool"
}

variable "provider_id" {
  type        = string
  description = "Workload Identity Pool Provider ID"
  default     = "github-provider"
}

variable "deployer_sa_name" {
  type        = string
  description = "Service Account ID for GHA deployer"
  default     = "gha-deployer"
}
