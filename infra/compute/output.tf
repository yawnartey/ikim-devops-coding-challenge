output "server_id" {
  value = hcloud_server.this.id
}

output "server_ipv4" {
  value = hcloud_server.this.ipv4_address
}
