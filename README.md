# MariaDB Terraform Module (Dockerized)

Manage MariaDB server.

* Runs in bridge networking mode
* Persists data directory
* Generates a random root password if not provided
* Automatic schema upgrades enabled (`MARIADB_AUTO_UPGRADE`)
* Healthcheck through the image's `healthcheck.sh`
* Files of the `FILE` privilege confined to the container's `/tmp` (`secure_file_priv`)


## Usage

See [examples/default](examples/default) for a complete working configuration.

```hcl
module "database" {
  source = "git::https://github.com/davidfischer-ch/terraform-module-dockerized-mariadb.git?ref=1.3.0"

  identifier = "my-app-database"
  image_id   = docker_image.mariadb.image_id

  # Networking

  hosts      = { "myserver" = "10.0.0.1" }
  network_id = docker_network.app.id

  # Storage

  data_directory = "/data/my-app/database"
}
```


## Data layout

All persistent data lives under `data_directory`:

```
data_directory/
├── backup/  # Dumps written by the backup action (/backup)
└── data/    # MariaDB data files (/var/lib/mysql)
```


## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `identifier` | `string` | — | Unique name for resources (must match `^[a-z]+(-[a-z0-9]+)*$`). |
| `enabled` | `bool` | `true` | Start or stop the container. |
| `wait` | `bool` | `true` | Wait for the container to reach a healthy state after creation. |
| `image_id` | `string` | — | [MariaDB](https://hub.docker.com/_/mariadb/tags) Docker image's ID. |
| `app_uid` | `number` | `999` | UID of the user running the container and owning the data directories. |
| `app_gid` | `number` | `999` | GID of the user running the container and owning the data directories. |
| `privileged` | `bool` | `false` | Run the container in privileged mode. |
| `cap_add` | `set(string)` | `[]` | Linux capabilities to add to the container, `ALL` for every one. |
| `cap_drop` | `set(string)` | `[]` | Linux capabilities to drop from the container, `ALL` for every one. |
| `hosts` | `map(string)` | `{}` | Extra `/etc/hosts` entries for the container. |
| `network_id` | `string` | — | Docker network to attach to. |
| `port` | `number` | `3306` | MariaDB port (changing not yet implemented). |
| `data_directory` | `string` | — | Host path for persistent volumes. |
| `secure_file_priv` | `string` | `"/tmp"` | Directory of the container the FILE statements read and write in; `null` lifts the limit, which lets a FILE account plant a dump in `/backup`. |
| `root_password` | `string` | `""` | Root password (auto-generated if empty, sensitive). |


## Outputs

| Name | Description |
|------|-------------|
| `host` | Container hostname. |
| `port` | MariaDB port. |
| `root_password` | Root password (sensitive). |


## Requirements

* Terraform >= 1.17
* [kreuzwerker/docker](https://github.com/kreuzwerker/terraform-provider-docker) >= 4.7.0
* [hashicorp/random](https://github.com/hashicorp/terraform-provider-random) >= 3.6.0


## Tests

```bash
terraform init -backend=false
terraform test
```

`terraform test` needs Terraform >= 1.17, the module's own floor. The tests plan against mocked
providers: they assert the healthcheck command, the root password the server is initialised with,
the capabilities passed to Docker and the outputs, and cover neither the image's `healthcheck.sh`
nor the data directory provisioner, which they do not run. They run on every push, in the GitHub
workflow (with the newest providers and with their minimums) and in the GitLab pipeline.

`tests/e2e/run.sh` applies the module against a real Docker daemon, checks the healthcheck, the root
password, the owner of the data directory and that the data outlives a replaced container, runs
every action on real data, then destroys everything. The GitHub workflow and the GitLab pipeline run
it on MariaDB 11.8 and 11.5; locally, as root:

```bash
E2E_IMAGE=mariadb:11.8.5 sh tests/e2e/run.sh
```

The Docker daemon must see the data directory at the same path: set `E2E_DATA_DIRECTORY` to a
directory on a filesystem both share when Terraform runs in a container of its own.


## Actions

On-demand operations on the server. Each runs only when invoked, never during an ordinary `apply`,
and leaves nothing in the state:

```bash
terraform apply -invoke='module.database.action.docker_exec.<action>'
```

Replace `module.database` with the module's address. Each runs as `app_uid:app_gid` and
authenticates as root with the password of the container's environment.

### Backup

Both work in `{data_directory}/backup`.

| Action | What it does | When |
|--------|--------------|------|
| `backup` | `mariadb-dump` of every database, then of the accounts but the image's own (`root`, `healthcheck`, `mariadb.sys`) with their grants, into `dump-<UTC time>.sql.tmp`, readable by `app_uid` alone, renamed `dump-<UTC time>.sql` once complete; the older dumps removed only then | Before an upgrade or a risky change, or on a schedule |
| `restore` | The newest complete dump loaded: its databases dropped and created again, its missing accounts created and its grants given, the existing accounts keeping their passwords | To roll the databases back to the last dump |

One dump is kept. To bring an older one back, restore it with restic into `{data_directory}/backup`
as the newest `dump-*.sql`, then invoke `restore`. A restore is not atomic: a failure, a row the
server rejects included, leaves the databases loaded up to the failing statement.

### Maintenance

| Action | What it does | When |
|--------|--------------|------|
| `check` | `mariadb-check --check`: every table of every database checked for corruption, failing when the report holds an error | After a crash, a disk error or a host change |
| `analyze` | `mariadb-check --analyze`: the key distribution statistics of every table | After a restore or a large load |
| `upgrade` | `mariadb-upgrade`: the system tables brought to the server's version | When the upgrade at start failed |

`MARIADB_AUTO_UPGRADE=true` already runs the upgrade when the container starts on a newer image.


## References

* https://hub.docker.com/_/mariadb
* https://github.com/davidfischer-ch/ansible-role-mariadb
