output "ssh_key_id" {
  value = hcloud_ssh_key.admin.id
}

output "firewall_id" {
  value = hcloud_firewall.server.id
}
