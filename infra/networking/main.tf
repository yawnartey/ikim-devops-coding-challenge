terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_primary_ip" "server" {
  name        = "${var.name}-ipv4"
  type        = "ipv4"
  location    = var.location
  auto_delete = false
}
