resource "docker_image" "mariadb" {
  name         = "mariadb:11.5.2"
  keep_locally = true
}

resource "docker_network" "app" {
  name   = "my-app"
  driver = "bridge"
}

resource "random_password" "mariadb_root" {
  length  = 32
  special = false
}

module "database" {
  source = "git::https://github.com/davidfischer-ch/terraform-module-dockerized-mariadb.git?ref=1.1.0"

  identifier = "my-app-database"
  image_id   = docker_image.mariadb.image_id

  # Networking

  network_id = docker_network.app.id

  # Storage

  data_directory = "/data/my-app/database"

  # Authentication

  root_password = random_password.mariadb_root.result
}
