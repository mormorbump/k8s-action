provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # google_billing_budget 等の Billing API は quota project が必要。
  # ADC (user credential) を使う場合、user_project_override を有効化し、
  # billing_project に対象プロジェクトを指定する。
  user_project_override = true
  billing_project       = var.project_id
}
