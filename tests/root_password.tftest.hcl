mock_provider "docker" {}
mock_provider "random" {}

variables {
  identifier     = "my-app-database"
  image_id       = "sha256:0123456789abcdef"
  network_id     = "my-app"
  data_directory = "/data/my-app/database"
}

override_resource {
  target          = random_password.root_password
  override_during = plan
  values = {
    result = "generated"
  }
}

run "given_root_password_initialises_the_server" {
  command = plan

  variables {
    root_password = "S3cret"
  }

  assert {
    condition     = contains(docker_container.server.env, "MARIADB_ROOT_PASSWORD=S3cret")
    error_message = "The server must be initialised with the root password the caller gives."
  }

  assert {
    condition     = output.root_password == "S3cret"
    error_message = "Output `root_password` must return the root password the caller gives."
  }
}

run "empty_root_password_is_generated" {
  command = plan

  assert {
    condition     = output.root_password == "generated"
    error_message = "Output `root_password` must return the generated password when none is given."
  }

  assert {
    condition     = contains(docker_container.server.env, "MARIADB_ROOT_PASSWORD=generated")
    error_message = "The server must be initialised with the generated password when none is given."
  }
}
