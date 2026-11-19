mock_provider "docker" {}
mock_provider "random" {}

variables {
  identifier     = "my-app-database"
  image_id       = "sha256:0123456789abcdef"
  network_id     = "my-app"
  data_directory = "/data/my-app/database"
}

run "healthcheck_runs_a_program_the_image_ships" {
  command = plan

  assert {
    condition = !strcontains(
      join(" ", docker_container.server.healthcheck[0].test), "mysqladmin"
    )
    error_message = join(" ", [
      "The official MariaDB images ship no mysqladmin from 11.0 on:",
      "the healthcheck must call healthcheck.sh.",
    ])
  }

  assert {
    condition = (
      docker_container.server.healthcheck[0].test[0] == "CMD"
      && docker_container.server.healthcheck[0].test[1] == "healthcheck.sh"
    )
    error_message = "The healthcheck must call the image's healthcheck.sh."
  }
}
