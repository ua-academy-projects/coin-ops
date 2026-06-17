# Configuration Schema

This directory contains JSON Schema files used to validate configuration files from `configs/`.
These schemas define common structure, allowed values, and validation rules for supported configuration types.

## Schemas

### `base.schema.json`

Contains main parameters, common for each configuration.

### `defs.json`

Contains definitions of rules used for validation configurations.

### `k3s.schema.json`

Contains schema for `k3s.json` configuration. Uses `base.schema.json` for common fields and adds validation rules for k3s-specific sections.

### `vm.schema.json`

Contains schema for VM-based configurations such as `vm.json`, `vm-multicloud.json`, and `test.json`. Uses `base.schema.json` for common fields and adds validation rules for VM-specific sections.
