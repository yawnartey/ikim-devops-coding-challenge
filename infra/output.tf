output "server_ip" {
  value = module.compute.server_ipv4
}

output "backup_bucket" {
  value = module.storage.bucket_name
}