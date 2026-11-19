resource "docker_container" "server" {

  image = var.image_id
  name  = var.identifier

  command = compact([
    "mariadbd",
    var.secure_file_priv == null ? "" : "--secure-file-priv=${var.secure_file_priv}",
  ])

  must_run = var.enabled
  start    = var.enabled
  restart  = "always"
  wait     = var.wait

  healthcheck {
    test         = ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 3
    start_period = "5m"
  }

  privileged = var.privileged

  dynamic "capabilities" {
    for_each = length(var.cap_add) + length(var.cap_drop) > 0 ? [1] : []
    content {
      add  = [for cap in var.cap_add : cap == "ALL" ? cap : "CAP_${cap}"]
      drop = [for cap in var.cap_drop : cap == "ALL" ? cap : "CAP_${cap}"]
    }
  }

  user = "${var.app_uid}:${var.app_gid}"

  # shm_size = 256 # MB

  env = [
    "MARIADB_AUTO_UPGRADE=true",
    "MARIADB_ROOT_PASSWORD=${local.root_password}"
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
