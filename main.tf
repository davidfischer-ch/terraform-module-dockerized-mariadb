resource "docker_container" "server" {

  image = var.image_id
  name  = var.identifier

  # command = []

  must_run = var.enabled
  start    = var.enabled
  restart  = "always"
  wait     = var.wait

  healthcheck {
    test         = ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -P ${var.port} --silent"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 3
    start_period = "5m"
  }

  privileged = var.privileged

  dynamic "capabilities" {
    for_each = length(var.cap_add) + length(var.cap_drop) > 0 ? [1] : []
    content {
      add  = [for cap in var.cap_add : "CAP_${cap}"]
      drop = [for cap in var.cap_drop : "CAP_${cap}"]
    }
  }

  user = "${var.app_uid}:${var.app_gid}"

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

  network_mode = "bridge"

  volumes {
    container_path = local.container_data_directory
    host_path      = local.host_data_directory
    read_only      = false
  }

  depends_on = [terraform_data.data_directories]
}
