# Changelog

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
