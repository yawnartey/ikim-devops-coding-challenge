variable "name" {
  description = "Base name used for networking resources"
  type        = string
}

variable "location" {
  description = "Hetzner datacenter to reserve the primary IP in"
  type        = string
}
