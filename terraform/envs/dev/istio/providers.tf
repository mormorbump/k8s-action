# GCP 認証情報（ADC 経由）を取得
data "google_client_config" "default" {}

# GKE 側 state から作成済みクラスタの情報を取得
data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.cluster_location
  project  = var.project_id
}

provider "google" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id
}

# Helm provider はクラスタに直接話しかける。
# クラスタの endpoint / CA / token を data source 経由で取得する。
# これによって "module.gke を作る apply" と "Helm を入れる apply" を
# 同一 state にしないで済む（chicken-and-egg 回避）。
provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.this.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.this.master_auth[0].cluster_ca_certificate
    )
  }
}
