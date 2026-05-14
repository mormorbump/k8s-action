variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Region for the subnet"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "preview"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary CIDR for the subnet (Node IPs)"
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR for Pods"
  default     = "10.4.0.0/22"
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR for Services (ClusterIPs)"
  default     = "10.8.0.0/22"
}
