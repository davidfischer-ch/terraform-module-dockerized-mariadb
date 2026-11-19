output "host" {
  description = "Hostname of the MariaDB container."
  value       = docker_container.server.hostname
}

output "port" {
  description = "Port bound by MariaDB."
  value       = var.port
}

output "root_password" {
  description = "MariaDB root password (the given one, or the generated one)."
  sensitive   = true
  value       = local.root_password
}
