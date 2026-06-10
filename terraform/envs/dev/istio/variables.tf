variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary region"
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "Existing GKE cluster name (created by envs/dev/gcp)"
  default     = "preview"
}

variable "cluster_location" {
  type        = string
  description = "Existing GKE cluster zone/region"
  default     = "us-central1-a"
}

variable "istio_version" {
  type        = string
  description = "Istio Helm chart version"
  default     = "1.27.0"
}
