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

variable "cleanup_keep_count" {
  type        = number
  description = "直近この数のイメージバージョンは無条件で残す"
  default     = 20
}

variable "cleanup_older_than_days" {
  type        = number
  description = "この日数より古いイメージは（keep 分を除き）削除する"
  default     = 14
}

resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.location
  repository_id = var.name
  format        = "DOCKER"
  description   = var.description

  # PR ごとに head SHA タグのイメージが push され、PR クローズ後も残り続ける。
  # (k8s の namespace と違い GAR は GitOps の prune 対象外のため自動では消えない)
  # ストレージ課金とイメージ一覧の肥大化を防ぐため cleanup policy で自動削除する。
  cleanup_policy_dry_run = false

  # 直近 N 個は無条件で残す（KEEP は DELETE より優先される）
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.cleanup_keep_count
    }
  }

  # 上で残す分を除き、一定期間より古いバージョンを削除
  cleanup_policies {
    id     = "delete-old-versions"
    action = "DELETE"
    condition {
      older_than = "${var.cleanup_older_than_days * 24 * 60 * 60}s"
    }
  }
}

output "repository_id" {
  value       = google_artifact_registry_repository.this.repository_id
  description = "Repository ID"
}

output "repository_url" {
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${var.name}"
  description = "Repository URL for docker push/pull"
}
