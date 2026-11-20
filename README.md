# MariaDB Terraform Module (Dockerized)

Manage MariaDB server.

* Runs in bridge networking mode
* Persists data directory
* Generates a random root password if not provided
* Root password in a file out of the container's configuration (`MARIADB_ROOT_PASSWORD_FILE`)
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
├── backup/            # Dumps written by the backup action (/backup)
├── data/              # MariaDB data files (/var/lib/mysql)
└── secrets/           # 0700, owned by app_uid:app_gid
    └── root-password  # 0600, owned by app_uid:app_gid (/run/secrets/root-password)
```

The root password reaches the server through `MARIADB_ROOT_PASSWORD_FILE` and the file, mounted
read-only: it is in neither the container's environment nor `docker inspect`. A `local-exec`
provisioner writes it once the other directories exist. The provisioner receives the password
through its environment, writes it without a trailing line feed under a temporary name, closed and
given to `app_uid:app_gid`, then renames it over the file. It writes the file again at each change
of the password, of `data_directory`, of `app_uid` or of `app_gid`, and when the file is absent.
Each write replaces the container, which binds the file by its inode. A destroy removes the file,
and `secrets/` once empty.

The state holds the password under a sensitive mark and no digest of it; the plan and the apply
print neither. The entrypoint and the actions read the file through a command substitution, which
drops trailing line feeds: `root_password` refuses a value ending with a line feed or a carriage
return.

Each plan reads the mode and owner of `secrets/` and of the file on the Terraform host, through
`hashicorp/external`. A mode or an owner changed while the password was not plans the replacement of
`terraform_data.root_password_access`, whose apply restores them and keeps the container; the next
plan is clean. The content of the file is not compared: one edited out of band stays until the next
write.


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
| `root_password` | `string` | `""` | Root password (auto-generated if empty, sensitive), ending with neither a line feed nor a carriage return. |


## Outputs

| Name | Description |
|------|-------------|
| `host` | Container hostname. |
| `port` | MariaDB port. |
| `root_password` | Root password (sensitive). |


## Requirements

* Terraform >= 1.17
* [kreuzwerker/docker](https://github.com/kreuzwerker/terraform-provider-docker) >= 4.7.0
* [hashicorp/external](https://github.com/hashicorp/terraform-provider-external) >= 2.3.0
* [hashicorp/random](https://github.com/hashicorp/terraform-provider-random) >= 3.6.0


## Tests

```bash
terraform init -backend=false
terraform test
```

`terraform test` needs Terraform >= 1.17, the module's own floor. The tests plan against mocked
providers: they assert the healthcheck command, the root password the password file holds, under a
sensitive mark and in no other attribute, the file mounted read-only and named by
`MARIADB_ROOT_PASSWORD_FILE`, a password ending with a line feed or a carriage return refused, the
paths the destroy removes, the mode and owner changes a plan restores and the absent file it writes
again, the capabilities passed to Docker and the outputs. They cover neither the image's
`healthcheck.sh` nor the provisioners, which they do not run. They run on every push, in the GitHub
workflow (with the newest providers and with their minimums) and in the GitLab pipeline.

`tests/e2e/run.sh` applies the module against a real Docker daemon, checks the healthcheck, the root
password, the owner of the data directory and that the data outlives a replaced container. It checks
that the password is out of the container's configuration, that neither the apply's output nor
`terraform show` holds it or its MD5, SHA-1, SHA-256 or SHA-512 digest, in hex or in base64, and
that the state holds the password under a sensitive mark alone and none of its digests. It runs
every action on real data. It opens `secrets/` and then the password file to other users, and gives
the file to another owner: each change shows in a plan and an apply restores it, keeping the
container, with a clean plan after. It checks that the actions read a file ending with a line feed,
and that a root password changed on the server and then given to the module replaces the container,
which binds the new file the actions read. It then destroys everything and checks that the password
file and `secrets/` are gone. The GitHub workflow and the GitLab pipeline run it on MariaDB 11.8 and
11.5; locally, as root, with `jq` and `openssl` installed:

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
authenticates as root with the password file the container mounts.

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
