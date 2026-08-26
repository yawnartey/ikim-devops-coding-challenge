variable "name" {
  type = string
}

variable "admin_cidr" {
  description = "IP addr in CIDR form. 203.0.113.5/32"
  type        = string
}

variable "ssh_public_key" {
  type = string
}
