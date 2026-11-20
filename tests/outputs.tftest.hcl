mock_provider "docker" {}
mock_provider "external" {
  source = "./tests/mocks"
}
mock_provider "random" {}

variables {
  identifier     = "my-app-database"
  image_id       = "sha256:0123456789abcdef"
  network_id     = "my-app"
  data_directory = "/data/my-app/database"
}

run "outputs_describe_the_server" {
  command = plan

  assert {
    condition     = output.host == "my-app-database"
    error_message = "`host` must be the container's hostname, its identifier."
  }

  assert {
    condition     = output.port == 3306
    error_message = "`port` must be the MariaDB port."
  }
}
