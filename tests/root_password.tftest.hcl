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
    condition     = nonsensitive(terraform_data.root_password.triggers_replace[0]) == "S3cret"
    error_message = "The password file must hold the root password the caller gives."
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
    condition     = nonsensitive(terraform_data.root_password.triggers_replace[0]) == "generated"
    error_message = "The password file must hold the generated password when none is given."
  }
}

run "root_password_reaches_the_server_through_a_read_only_file" {
  command = plan

  assert {
    condition = anytrue([
      for volume in docker_container.server.volumes :
      volume.host_path == "/data/my-app/database/secrets/root-password"
      && volume.container_path == "/run/secrets/root-password"
      && volume.read_only
    ])
    error_message = "The container must mount the password file read-only."
  }

  assert {
    condition = contains(
      docker_container.server.env, "MARIADB_ROOT_PASSWORD_FILE=/run/secrets/root-password"
    )
    error_message = "The image's entrypoint must read the root password from the mounted file."
  }
}

run "root_password_is_in_no_attribute_in_clear" {
  command = plan

  variables {
    root_password = "S3cret"
  }

  assert {
    condition = !anytrue(concat(
      [for env in docker_container.server.env : strcontains(env, "S3cret")],
      [for argument in docker_container.server.command : strcontains(argument, "S3cret")],
    ))
    error_message = "The root password must stay out of the container's environment and command."
  }

  assert {
    condition = (
      issensitive(terraform_data.root_password.triggers_replace[0])
      && slice(terraform_data.root_password.triggers_replace, 1, 4) == [
        "/data/my-app/database/secrets/root-password", "999:999", ""
      ]
    )
    error_message = "The password file's triggers must hold the root password marked sensitive."
  }

  assert {
    condition     = terraform_data.root_password_access.triggers_replace == [""]
    error_message = "The step restoring the access to the password file must not hold it."
  }
}

run "root_password_ending_with_a_line_feed_is_refused" {
  command = plan

  variables {
    root_password = "pw\n"
  }

  expect_failures = [var.root_password]
}

run "root_password_ending_with_a_carriage_return_is_refused" {
  command = plan

  variables {
    root_password = "pw\r"
  }

  expect_failures = [var.root_password]
}

run "password_file_is_given_to_app_uid" {
  command = plan

  variables {
    app_uid = 1001
    app_gid = 1002
  }

  assert {
    condition     = contains(terraform_data.root_password.triggers_replace, "1001:1002")
    error_message = "The password file must be written again at each change of app_uid:app_gid."
  }

  assert {
    condition = local.root_password_access == {
      directory = "700 1001:1002"
      file      = "600 1001:1002"
    }
    error_message = "The secrets directory and the password file must belong to app_uid:app_gid."
  }
}

run "destroy_removes_the_password_file" {
  command = plan

  assert {
    condition = terraform_data.root_password.input == {
      directory = "/data/my-app/database/secrets"
      file      = "/data/my-app/database/secrets/root-password"
    }
    error_message = "The destroy provisioner must reach the password file and its directory."
  }
}

run "unchanged_access_plans_nothing" {
  command = plan

  assert {
    condition     = !local.root_password_absent && !local.root_password_drifted
    error_message = "A directory at 700 and a file at 600, owned by app_uid, must plan nothing."
  }
}

run "opened_directory_is_restored" {
  command = plan

  override_data {
    target = data.external.root_password_access
    values = {
      result = { directory = "755 999:999", file = "600 999:999" }
    }
  }

  assert {
    condition     = !local.root_password_absent && local.root_password_drifted
    error_message = "A secrets directory opened to other users must be restored, the file kept."
  }
}

run "opened_file_is_restored" {
  command = plan

  override_data {
    target = data.external.root_password_access
    values = {
      result = { directory = "700 999:999", file = "644 999:999" }
    }
  }

  assert {
    condition     = !local.root_password_absent && local.root_password_drifted
    error_message = "A password file opened to other users must be restored, not written again."
  }
}

run "file_of_another_owner_is_restored" {
  command = plan

  override_data {
    target = data.external.root_password_access
    values = {
      result = { directory = "700 999:999", file = "600 0:0" }
    }
  }

  assert {
    condition     = !local.root_password_absent && local.root_password_drifted
    error_message = "A password file given to another owner must be restored, not written again."
  }
}

run "absent_file_is_written" {
  command = plan

  override_data {
    target = data.external.root_password_access
    values = {
      result = { directory = "absent", file = "absent" }
    }
  }

  assert {
    condition     = local.root_password_absent && !local.root_password_drifted
    error_message = "An absent password file must be written, not restored."
  }
}
