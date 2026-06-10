module "istio" {
  source        = "../../../modules/istio"
  istio_version = var.istio_version
}
