output "host" {
  value = docker_container.server.hostname
}

output "port" {
  value = var.port
}

output "root_password" {
  value     = random_password.root_password.result
  sensitive = true
}
