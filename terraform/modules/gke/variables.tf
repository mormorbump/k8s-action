variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "name" {
  type        = string
  description = "Cluster name"
  default     = "preview"
}

variable "zone" {
  type        = string
  description = "Zone for zonal cluster"
}

variable "network" {
  type        = string
  description = "VPC network ID"
}

variable "subnetwork" {
  type        = string
  description = "Subnet ID"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary IP range name for Pods"
}

variable "services_range_name" {
  type        = string
  description = "Secondary IP range name for Services"
}

variable "machine_type" {
  type        = string
  description = "Node machine type"
  default     = "e2-medium"
}

variable "node_count" {
  type        = number
  description = "Number of nodes per zone"
  default     = 2
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size per node"
  default     = 50
}

variable "release_channel" {
  type        = string
  description = "GKE release channel"
  default     = "REGULAR"
}
