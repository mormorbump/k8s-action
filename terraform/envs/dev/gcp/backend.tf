terraform {
  backend "gcs" {
    bucket = "k8s-action-preview-26-tfstate"
    prefix = "envs/dev/gcp"
  }
}
