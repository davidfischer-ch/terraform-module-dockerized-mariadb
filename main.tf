resource "docker_container" "server" {

  image = var.image_id
  name  = var.identifier

  # command = []

  must_run = var.enabled
  start    = var.enabled
  restart  = "always"
  wait     = var.wait

  # shm_size = 256 # MB

  env = [
    "MARIADB_AUTO_UPGRADE=true",
    "MARIADB_ROOT_PASSWORD=${random_password.root_password.result}"
  ]

  dynamic "host" {
    for_each = var.hosts
    content {
      host = host.key
      ip   = host.value
    }
  }

  hostname = var.identifier

  networks_advanced {
    name = var.network_id
  }

  # Data
  volumes {
    container_path = local.container_data_directory
    host_path      = local.host_data_directory
    read_only      = false
  }
}
