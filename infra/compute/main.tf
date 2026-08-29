terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_server" "this" {
  name         = var.name
  server_type  = var.server_type
  user_data = templatefile("${path.module}/bootstrap.sh", {
    github_token = var.github_token
    sops_age_key = var.sops_age_key
  })
  image        = var.image
  location     = var.location
  ssh_keys     = var.ssh_key_ids
  firewall_ids = var.firewall_ids

  public_net {
    ipv4_enabled = true
    ipv4         = var.primary_ip_id
    ipv6_enabled = false
  }
}
