terraform {
  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# aws provider for a bucket in hetzner
provider "aws" {
  alias      = "hetzner"
  region     = var.location
  access_key = var.hetzner_s3_access_key
  secret_key = var.hetzner_s3_secret_key

  endpoints {
    s3 = "https://${var.location}.your-objectstorage.com"
  }

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
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

# storage module
module "storage" {
  source      = "./storage"
  bucket_name = "${var.project_name}-backups"

  providers = {
    aws = aws.hetzner
  }
}