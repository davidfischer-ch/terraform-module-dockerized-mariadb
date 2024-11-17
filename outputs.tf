output "host" {
  value = docker_container.server.hostname
}

output "port" {
  value = var.port
}

output "name" {
  value = var.name
}

output "user" {
  value = var.user
}

output "password" {
  value     = var.password
  sensitive = true
}

output "root_password" {
  value     = random_password.root_password.result
  sensitive = true
}
