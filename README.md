# MariaDB Terraform Module (Dockerized)

Manage MariaDB server.

* Runs in bridge networking mode
* Persists data directory
* Generates a random root password if not provided
* Automatic schema upgrades enabled (`MARIADB_AUTO_UPGRADE`)

## Usage

See [examples/default](examples/default) for a complete working configuration.

```hcl
module "database" {
  source = "git::https://github.com/davidfischer-ch/terraform-module-dockerized-mariadb.git?ref=1.0.2"

  identifier     = "my-app-database"
  enabled        = true
  image_id       = docker_image.mariadb.image_id
  data_directory = "/data/my-app/database"

  hosts      = { "myserver" = "10.0.0.1" }
  network_id = docker_network.app.id
}
```

## Data layout

All persistent data lives under `data_directory`:

```
data_directory/
└── data/  # MariaDB data files (/var/lib/mysql)
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `identifier` | `string` | — | Unique name for resources (must match `^[a-z]+(-[a-z0-9]+)*$`). |
| `enabled` | `bool` | — | Start or stop the container. |
| `wait` | `bool` | `false` | Wait for the container to reach a healthy state after creation. |
| `image_id` | `string` | — | [MariaDB](https://hub.docker.com/_/mariadb/tags) Docker image's ID. |
| `data_directory` | `string` | — | Host path for persistent volumes. |
| `data_owner` | `string` | `"999:999"` | UID:GID for data directories. |
| `root_password` | `string` | `""` | Root password (auto-generated if empty, sensitive). |
| `hosts` | `map(string)` | `{}` | Extra `/etc/hosts` entries for the container. |
| `network_id` | `string` | — | Docker network to attach to. |
| `port` | `number` | `3306` | MariaDB port (changing not yet implemented). |

## Outputs

| Name | Description |
|------|-------------|
| `host` | Container hostname. |
| `port` | MariaDB port. |
| `root_password` | Root password (sensitive). |

## Requirements

* Terraform >= 1.6
* [kreuzwerker/docker](https://github.com/kreuzwerker/terraform-provider-docker) >= 3.0.2
* [hashicorp/random](https://github.com/hashicorp/terraform-provider-random) >= 3.6.0

## References

* https://hub.docker.com/_/mariadb
* https://github.com/davidfischer-ch/ansible-role-mariadb
