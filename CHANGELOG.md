# Changelog


## Release v1.3.0 (2026-11-19)

Diff: https://github.com/davidfischer-ch/terraform-module-dockerized-mariadb/compare/1.2.0...1.3.0

### Minor compatibility breaks

Server:

* Confine the `FILE` statements to the container's `/tmp`, through the new `secure_file_priv` input (`null` lifts the limit)

### Features

Actions:

* Add `backup` and `restore` actions, through a time-stamped dump in `{data_directory}/backup`
    * The container is replaced once on upgrade, to mount `{data_directory}/backup`
    * The dump holds every database, then the accounts with their grants but the image's own, readable by `app_uid` alone
    * Restore keeps the passwords of the existing accounts and fails on a row the server rejects
* Add `check`, `analyze` and `upgrade` maintenance actions

CI:

* Add CI: formatting, validation and the tests, in the GitHub workflow (with the newest providers and their minimums) and in the GitLab pipeline
* Add an end-to-end test of the module and its actions against a real Docker daemon, on MariaDB 11.8 and 11.5

### Fix and enhancements

Server:

* Report the server healthy on MariaDB 11, through the image's `healthcheck.sh`
    * An image too old to ship `healthcheck.sh` turns unhealthy, and with `wait` the apply fails
* Start the server with the given `root_password` instead of a generated one
    * MariaDB ignores it on an existing data directory: the server keeps its password while the `root_password` output returns the given one
* Pass `ALL` in `cap_add` and `cap_drop` to Docker as its wildcard instead of `CAP_ALL`
* Hand the data directory over again, recursively, when `app_uid` or `app_gid` changes, whatever its path holds
    * The first apply after the upgrade runs `chown -R` over the data directory

Requirements:

* Require Terraform 1.17
* Require the Docker provider 4.7.0

Docs:

* Document `ALL` in `cap_add` and `cap_drop`
* Point the README and the examples at this release


## Release v1.2.0 (2026-03-14)

### Minor compatibility breaks

* Remove the `CAP_` prefix from `cap_add` and `cap_drop` values — the module now adds it automatically when calling the Docker provider

### Fix and enhancements

* Add validation of `cap_add` and `cap_drop` against the exhaustive list of Linux capabilities
* Reorder variables to be consistent

## Release v1.1.1 (2026-03-13)

### Features

* Add Docker healthcheck using `mysqladmin ping` on `var.port` (start period: 5 minutes)

### Fix and enhancements

* Set `enabled` and `wait` defaults to `true`
* Refine variable descriptions, validators, and attribute ordering
* Remove redundant default values from examples and README

## Release v1.1.0 (2026-03-13)

### Breaking changes

* Replace `data_owner` by `app_uid`, `app_gid` with the same default values of `999`

### Fix and enhancements

* Add `# Process` section: `app_uid`, `app_gid`, `privileged`, `cap_add`, `cap_drop`
  variables wired into the container via `user`, `privileged`, and a dynamic `capabilities` block
* Add `examples/default/` Terraform example

## Release v1.0.2 (2026-03-02)

### Features

* Add `data_owner` variable to parameterize data directory ownership

## Release v1.0.1 (2026-01-03)

### Fix and enhancements

* Module: Declare network_mode bridge to prevent infinite recreate

## Release v1.0.0 (2025-01-20)

Initial release
