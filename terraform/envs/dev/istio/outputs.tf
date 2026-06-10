output "istio_version" {
  value       = module.istio.istio_version
  description = "Installed Istio version"
}

output "system_namespace" {
  value       = module.istio.system_namespace
  description = "Namespace where istiod runs"
}

output "ingress_namespace" {
  value       = module.istio.ingress_namespace
  description = "Namespace where Istio Ingress Gateway runs"
}
