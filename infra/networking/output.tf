output "primary_ip_id" {
  description = "ID of the reserved primary IPv4 for the compute module to attach"
  value       = hcloud_primary_ip.server.id
}

output "primary_ip_address" {
  description = "The reserved public IPv4 address"
  value       = hcloud_primary_ip.server.ip_address
}
