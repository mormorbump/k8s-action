variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "location" {
  type        = string
  description = "Region for the repository"
}

variable "name" {
  type        = string
  description = "Repository ID"
  default     = "preview"
}

variable "description" {
  type        = string
  description = "Repository description"
  default     = "Container images for preview environments"
}

resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.location
  repository_id = var.name
  format        = "DOCKER"
  description   = var.description
}

output "repository_id" {
  value       = google_artifact_registry_repository.this.repository_id
  description = "Repository ID"
}

output "repository_url" {
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${var.name}"
  description = "Repository URL for docker push/pull"
}
