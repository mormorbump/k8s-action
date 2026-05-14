variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "apis" {
  type        = list(string)
  description = "List of APIs to enable"
}

resource "google_project_service" "this" {
  for_each = toset(var.apis)

  project = var.project_id
  service = each.value

  # 学習用: destroy 時に他リソースを巻き込まないよう false
  disable_dependent_services = false
  disable_on_destroy         = false
}
