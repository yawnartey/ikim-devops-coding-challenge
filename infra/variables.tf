variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Hetzner location to provision into"
  type        = string
  default     = "fsn1"
}

variable "project_name" {
  description = "Base name applied to all resources"
  type        = string
  default     = "openbao-platform"
}

variable "admin_cidr" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
