terraform {
  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# networking module
module "networking" {
  source   = "./networking"
  name     = var.project_name
  location = var.location
}

# networking module
module "security" {
  source         = "./security"
  name           = var.project_name
  admin_cidr     = var.admin_cidr
  ssh_public_key = var.ssh_public_key
}

# compute module
module "compute" {
  source        = "./compute"
  name          = var.project_name
  location      = var.location
  ssh_key_ids   = [module.security.ssh_key_id]
  firewall_ids  = [module.security.firewall_id]
  primary_ip_id = module.networking.primary_ip_id
  github_token = var.github_token
}
