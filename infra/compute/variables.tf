variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "server_type" {
  type    = string
  default = "ccx23"
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "ssh_key_ids" {
  type = list(number)
}

variable "firewall_ids" {
  type = list(number)
}

variable "primary_ip_id" {
  type = number
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "sops_age_key" {
  type      = string
  sensitive = true
}