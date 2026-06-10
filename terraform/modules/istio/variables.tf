variable "istio_version" {
  type        = string
  description = "Istio Helm chart version (e.g., 1.27.0). See ADR-0002."
  default     = "1.27.0"
}

variable "system_namespace" {
  type        = string
  description = "Namespace for istiod and istio-base"
  default     = "istio-system"
}

variable "ingress_namespace" {
  type        = string
  description = "Namespace for the Istio Ingress Gateway"
  default     = "istio-ingress"
}

variable "istiod_cpu_request" {
  type        = string
  description = "CPU request for istiod (default Istio: 500m, lowered for learning)"
  default     = "100m"
}

variable "istiod_memory_request" {
  type        = string
  description = "Memory request for istiod (default Istio: 2048Mi, lowered for learning)"
  default     = "256Mi"
}

variable "gateway_cpu_request" {
  type        = string
  description = "CPU request for Istio Ingress Gateway"
  default     = "100m"
}

variable "gateway_memory_request" {
  type        = string
  description = "Memory request for Istio Ingress Gateway"
  default     = "128Mi"
}
