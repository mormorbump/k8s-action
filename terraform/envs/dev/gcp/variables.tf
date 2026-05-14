variable "project_id" {
  type        = string
  description = "GCP project ID (must exist; created manually outside Terraform)"
}

variable "region" {
  type        = string
  description = "Primary region"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "Zone for zonal cluster"
  default     = "us-central1-a"
}

variable "gke_machine_type" {
  type        = string
  description = "Machine type for GKE nodes"
  default     = "e2-medium"
}

variable "gke_node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
  default     = 2
}

variable "github_owner" {
  type        = string
  description = "GitHub user/organization (for WIF)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (for WIF)"
}

variable "billing_account" {
  type        = string
  description = "Billing account ID (for Budget Alert)"
}

variable "budget_monthly_amount" {
  type        = number
  description = "Monthly budget amount (in currency units of the billing account)"
  default     = 7500
}

variable "budget_currency_code" {
  type        = string
  description = "Currency code matching the billing account (e.g., JPY, USD)"
  default     = "JPY"
}
