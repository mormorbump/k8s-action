resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.zone

  # デフォルト node pool を作らず、別途カスタム pool を管理
  remove_default_node_pool = true
  initial_node_count       = 1

  # 学習用: destroy できるよう false 明示
  deletion_protection = false

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native (IP alias) で Pod/Service の secondary range を指定
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  # 学習用に最小限のロギング・モニタリング
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
}

resource "google_container_node_pool" "default" {
  project    = var.project_id
  name       = "default"
  cluster    = google_container_cluster.this.name
  location   = var.zone
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"

    # Workload Identity 用に GKE_METADATA 必須
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "dev"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}
