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
  source = "git::https://github.com/davidfischer-ch/terraform-module-dockerized-mariadb.git?ref=1.0.2"

  identifier     = "my-app-database"
  enabled        = true
  image_id       = docker_image.mariadb.image_id
  data_directory = "/data/my-app/database"

  network_id    = docker_network.app.id
  root_password = random_password.mariadb_root.result
}
