locals {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
}

module "project_services" {
  source     = "../../../modules/project_services"
  project_id = local.project_id

  apis = [
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "billingbudgets.googleapis.com",
    "storage.googleapis.com",
  ]
}

module "network" {
  source     = "../../../modules/network"
  project_id = local.project_id
  region     = local.region

  depends_on = [module.project_services]
}

module "gke" {
  source              = "../../../modules/gke"
  project_id          = local.project_id
  zone                = local.zone
  network             = module.network.network_id
  subnetwork          = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  machine_type        = var.gke_machine_type
  node_count          = var.gke_node_count

  depends_on = [module.network]
}

module "artifact_registry" {
  source     = "../../../modules/artifact_registry"
  project_id = local.project_id
  location   = local.region

  depends_on = [module.project_services]
}

module "workload_identity" {
  source       = "../../../modules/workload_identity"
  project_id   = local.project_id
  github_owner = var.github_owner
  github_repo  = var.github_repo

  depends_on = [module.project_services]
}

module "budget" {
  source          = "../../../modules/budget"
  project_id      = local.project_id
  billing_account = var.billing_account
  monthly_amount  = var.budget_monthly_amount
  currency_code   = var.budget_currency_code

  depends_on = [module.project_services]
}
