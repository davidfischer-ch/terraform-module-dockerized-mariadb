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

run "file_statements_stay_in_tmp_by_default" {
  command = plan

  assert {
    condition = docker_container.server.command == tolist([
      "mariadbd", "--secure-file-priv=/tmp",
    ])
    error_message = "The FILE statements must reach the container's /tmp only, out of /backup."
  }
}

run "file_statements_go_where_the_caller_says" {
  command = plan

  variables {
    secure_file_priv = "/var/lib/mysql-files"
  }

  assert {
    condition = docker_container.server.command == tolist([
      "mariadbd", "--secure-file-priv=/var/lib/mysql-files",
    ])
    error_message = "`secure_file_priv` must reach the server's command line."
  }
}

run "null_lifts_the_limit" {
  command = plan

  variables {
    secure_file_priv = null
  }

  assert {
    condition     = docker_container.server.command == tolist(["mariadbd"])
    error_message = "A null `secure_file_priv` must leave the server's default."
  }
}

run "relative_directory_is_refused" {
  command = plan

  variables {
    secure_file_priv = "tmp"
  }

  expect_failures = [var.secure_file_priv]
}
