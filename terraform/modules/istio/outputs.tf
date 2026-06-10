output "system_namespace" {
  value       = var.system_namespace
  description = "Namespace where istiod runs"
}

output "ingress_namespace" {
  value       = var.ingress_namespace
  description = "Namespace where Istio Ingress Gateway runs"
}

output "istio_version" {
  value       = var.istio_version
  description = "Installed Istio version"
}
