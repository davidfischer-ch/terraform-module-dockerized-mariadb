output "host" {
  description = "Hostname of the MariaDB container."
  value       = docker_container.server.hostname
}

output "port" {
  description = "Port bound by MariaDB."
  value       = var.port
}

output "root_password" {
  description = "Generated MariaDB root password."
  sensitive   = true
  value       = random_password.root_password.result
}
